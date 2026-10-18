#!/bin/bash
# Seeds: registry:2 on :5000 (Docker Hub/ECR stand-in), MinIO on :9000 with bucket
# tf-state (S3 stand-in), a pre-built "lab-server" image that Terraform's docker
# provider turns into the "EC2" server, an SSH key pair, Jenkins in Docker (:8081)
# with Maven + docker CLI + terraform + ssh-agent and the course credentials, a
# starter repo (course code minus Jenkinsfile and Terraform solution) and a
# pipeline job pointing at it. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE

APP_REPO=https://gitlab.com/twn-devops-bootcamp/latest/12-terraform/java-maven-app.git
APP_SHA=660fa3b392e4513e6afcba7fe2394e23f1b1b60b   # branch jenkinsfile-sshagent
JENKINS_IMAGE=jenkins/jenkins:2.541.3-lts-jdk17
MAVEN_IMAGE=maven:3.9.11-eclipse-temurin-17
DOCKER_CLI_IMAGE=docker:27.5.1-cli
TERRAFORM_IMAGE=hashicorp/terraform:1.16.3
TF_DOCKER_PROVIDER=3.6.2
MINIO_IMAGE=bitnamilegacy/minio:2025.7.23-debian-12-r5
REGISTRY_IMAGE=registry:2.8.3
S3_KEY=labadmin
S3_SECRET=labsecret123
JH=/var/lib/jenkins-lab

# --- Docker ---
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done

# Pull everything in parallel while the rest is prepared.
for img in $JENKINS_IMAGE $MAVEN_IMAGE $DOCKER_CLI_IMAGE $TERRAFORM_IMAGE $MINIO_IMAGE $REGISTRY_IMAGE \
           ubuntu:24.04 amazoncorretto:17-alpine-jdk postgres:16; do
  docker pull -q "$img" >/dev/null &
done
wait

# --- Registry (Docker Hub / ECR stand-in) ---
docker rm -f registry 2>/dev/null || true
docker run -d --restart=always --name registry -p 5000:5000 $REGISTRY_IMAGE

# --- MinIO (S3 stand-in) with the state bucket ---
docker rm -f minio 2>/dev/null || true
docker run -d --restart=always --name minio -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=$S3_KEY -e MINIO_ROOT_PASSWORD=$S3_SECRET -e MINIO_DEFAULT_BUCKETS=tf-state \
  $MINIO_IMAGE

# --- Old lab leftovers (servers / app containers from a previous run) ---
docker ps -aq --filter ancestor=lab-server:1.0 | xargs -r docker rm -f
docker ps -aq --filter label=com.docker.compose.project | xargs -r docker rm -f

# --- "EC2" server image: ubuntu + sshd + docker CLI + compose, user ec2-user ---
mkdir -p /opt/lab-server
cat > /opt/lab-server/entrypoint.sh <<'EOF'
#!/bin/bash
# Like EC2's key_name: the public key handed in at creation becomes ec2-user's authorized key.
set -e
ssh-keygen -A >/dev/null
install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.ssh
if [ -n "$SSH_PUBLIC_KEY" ]; then
  printf '%s\n' "$SSH_PUBLIC_KEY" > /home/ec2-user/.ssh/authorized_keys
  chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
  chmod 600 /home/ec2-user/.ssh/authorized_keys
fi
# Let ec2-user use the Docker engine (like `usermod -aG docker ec2-user`).
if [ -S /var/run/docker.sock ]; then
  gid=$(stat -c %g /var/run/docker.sock)
  getent group "$gid" >/dev/null || groupadd -g "$gid" docker
  usermod -aG "$(getent group "$gid" | cut -d: -f1)" ec2-user
fi
exec /usr/sbin/sshd -D -e
EOF
chmod +x /opt/lab-server/entrypoint.sh
cat > /opt/lab-server/Dockerfile <<EOF
FROM $DOCKER_CLI_IMAGE AS dockercli
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server ca-certificates \\
 && rm -rf /var/lib/apt/lists/* \\
 && useradd -m -s /bin/bash ec2-user && usermod -p '*' ec2-user && mkdir -p /run/sshd \\
 && sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
RUN ln -s /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
COPY entrypoint.sh /entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
EOF
docker build -q -t lab-server:1.0 /opt/lab-server &
SERVER_BUILD=$!

# --- Jenkins image: LTS + Maven + docker CLI + terraform (provider pre-cached) ---
mkdir -p /opt/jenkins-lab
cat > /opt/jenkins-lab/Dockerfile <<EOF
FROM $DOCKER_CLI_IMAGE AS dockercli
FROM $MAVEN_IMAGE AS mvn
FROM $TERRAFORM_IMAGE AS tf
FROM $JENKINS_IMAGE
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=mvn /usr/share/maven /usr/share/maven
COPY --from=tf /bin/terraform /usr/local/bin/terraform
ENV TF_PLUGIN_CACHE_DIR=/opt/tf-plugin-cache TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1 TF_IN_AUTOMATION=1
RUN ln -s /usr/share/maven/bin/mvn /usr/local/bin/mvn
RUN mkdir -p /opt/tf-plugin-cache /tmp/tfwarm \\
 && printf 'terraform {\\n  required_providers {\\n    docker = { source = "kreuzwerker/docker", version = "$TF_DOCKER_PROVIDER" }\\n  }\\n}\\n' > /tmp/tfwarm/main.tf \\
 && cd /tmp/tfwarm && terraform init -backend=false -input=false && rm -rf /tmp/tfwarm
RUN jenkins-plugin-cli --plugins workflow-aggregator git credentials-binding plain-credentials ssh-credentials ssh-agent configuration-as-code
ENV JAVA_OPTS="-Xmx768m -Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF
docker build --progress=plain -t jenkins-lab /opt/jenkins-lab 2>&1 | tail -40; [ "${PIPESTATUS[0]}" = 0 ]
wait $SERVER_BUILD

# --- SSH key pair for the server (like the EC2 key pair) ---
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -f /root/.ssh/server-key ] || ssh-keygen -q -t ed25519 -N '' -C server-key -f /root/.ssh/server-key

# --- Starter app repo (course code, without the pipeline + Terraform solution) ---
rm -rf /root/java-maven-app
git clone -q "$APP_REPO" /root/java-maven-app
cd /root/java-maven-app
git checkout -q "$APP_SHA"
rm -rf .git Jenkinsfile terraform
mkdir terraform
cat > terraform/main.tf <<EOF
terraform {
  required_version = ">= 1.5"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "$TF_DOCKER_PROVIDER"
    }
  }
}

provider "docker" {}

# The "EC2 instance": an SSH server (user ec2-user) that runs Docker workloads.
resource "docker_container" "myapp-server" {
  name     = "\${var.env_prefix}-server"
  image    = var.server_image
  hostname = "\${var.env_prefix}-server"
  restart  = "unless-stopped"

  env = ["SSH_PUBLIC_KEY=\${file(var.public_key_location)}"]

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
}

output "ec2-public_ip" {
  value = docker_container.myapp-server.network_data[0].ip_address
}
EOF
cat > terraform/variables.tf <<'EOF'
variable env_prefix {
  default = "dev"
}
variable server_image {
  default = "lab-server:1.0"
}
variable public_key_location {
  default = "/home/nana/.ssh/id_rsa.pub"
}
EOF
git init -q -b master
git config user.email "you@example.com"; git config user.name "You"
git add -A && git commit -qm "starting code"
git config --global --add safe.directory /root/java-maven-app
cd /

# --- Jenkins config: admin user, Maven tool, course credentials ---
mkdir -p $JH/jobs/java-maven-app $JH/lab-secrets
cp /root/.ssh/server-key $JH/lab-secrets/server-key
chmod 600 $JH/lab-secrets/server-key
cat > $JH/casc.yaml <<EOF
jenkins:
  numExecutors: 2
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: admin
          password: admin
  authorizationStrategy: loggedInUsersCanDoAnything
unclassified:
  location:
    url: http://localhost:8081/
tool:
  maven:
    installations:
      - name: Maven
        home: /usr/share/maven
credentials:
  system:
    domainCredentials:
      - credentials:
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: server-ssh-key
              username: ec2-user
              description: SSH key for the server (ec2-user)
              privateKeySource:
                directEntry:
                  privateKey: "\${readFile:/var/jenkins_home/lab-secrets/server-key}"
          - string:
              scope: GLOBAL
              id: jenkins_aws_access_key_id
              description: AWS access key id (MinIO)
              secret: $S3_KEY
          - string:
              scope: GLOBAL
              id: jenkins-aws_secret_access_key
              description: AWS secret access key (MinIO)
              secret: $S3_SECRET
EOF
cat > $JH/jobs/java-maven-app/config.xml <<'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Builds the Jenkinsfile on master of /root/java-maven-app</description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig><url>file:///repos/java-maven-app</url></hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches><hudson.plugins.git.BranchSpec><name>*/master</name></hudson.plugins.git.BranchSpec></branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>false</lightweight>
  </definition>
  <disabled>false</disabled>
</flow-definition>
EOF

# Host network: Jenkins reaches the registry, MinIO and the server's IP the way the
# host does. Port 8081 because the app takes 8080 (docker-compose.yaml).
docker rm -f jenkins 2>/dev/null || true
docker run -d --restart=always --name jenkins --network host -u root \
  -e JENKINS_OPTS=--httpPort=8081 \
  -v $JH:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /root/java-maven-app:/repos/java-maven-app:ro \
  jenkins-lab
for i in $(seq 1 90); do
  curl -sf -u admin:admin http://localhost:8081/job/java-maven-app/api/json >/dev/null 2>&1 && break; sleep 3
done
curl -sf -u admin:admin http://localhost:8081/job/java-maven-app/api/json >/dev/null
docker exec jenkins git config --global --add safe.directory /repos/java-maven-app

# MinIO must be up with the bucket before we call it ready.
for i in $(seq 1 30); do
  docker exec -e MC_HOST_l=http://$S3_KEY:$S3_SECRET@localhost:9000 minio mc ls l/tf-state >/dev/null 2>&1 && break; sleep 2
done
docker exec -e MC_HOST_l=http://$S3_KEY:$S3_SECRET@localhost:9000 minio mc ls l/tf-state

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/bin/bash
# Pass when the latest Jenkins build is green, its Terraform state lives in the MinIO
# bucket and holds the server, and the server runs (via compose) the exact image that
# build pushed, answering on :8080.
fail() { echo "❌ NOT YET: $1"; exit 0; }
J="curl -s --max-time 10 -u admin:admin http://localhost:8081"
REPO=localhost:5000/java-maven-app
MC="docker exec -e MC_HOST_l=http://labadmin:labsecret123@localhost:9000 minio mc"

$J/api/json >/dev/null 2>&1 || fail "Jenkins is not answering on :8081 (docker ps / docker logs jenkins)."
last=$($J/job/java-maven-app/lastBuild/api/json 2>/dev/null)
[ -n "$last" ] || fail "The java-maven-app job has never run."
echo "$last" | grep -q '"building":true' && fail "A build is still running; wait for it to finish."
echo "$last" | grep -q '"result":"SUCCESS"' || fail "The latest java-maven-app build is not green."
num=$(echo "$last" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
log=$($J/job/java-maven-app/$num/consoleText 2>/dev/null)

# Terraform state must be in the S3 (MinIO) bucket and contain the server.
objs=$($MC ls -r --json l/tf-state 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    try: o = json.loads(line)
    except Exception: continue
    if o.get("type") == "file": print(o["key"])' 2>/dev/null)
[ -n "$objs" ] || fail "No Terraform state in the S3 bucket tf-state (is the pipeline using the S3 backend?)."
srv=""
for o in $objs; do
  srv=$($MC cat "l/tf-state/$o" 2>/dev/null | python3 -c '
import sys, json
try: s = json.load(sys.stdin)
except Exception: sys.exit()
for r in s.get("resources", []):
    if r.get("type") == "docker_container" and r.get("mode") == "managed":
        for i in r.get("instances", []):
            a = i.get("attributes", {})
            nd = a.get("network_data") or [{}]
            print(a.get("id", ""), a.get("name", ""), nd[0].get("ip_address", ""))
            sys.exit()' 2>/dev/null)
  [ -n "$srv" ] && break
done
[ -n "$srv" ] || fail "The state in bucket tf-state does not contain the server (a docker_container resource)."
read -r sid sname sip <<<"$srv"

# The server Terraform created must exist and be running.
[ "$(docker inspect -f '{{.State.Running}}' "$sid" 2>/dev/null)" = true ] \
  || fail "The server '$sname' recorded in the Terraform state is not running (docker ps -a)."
[ "$(docker inspect -f '{{.Image}}' "$sid")" = "$(docker image inspect -f '{{.Id}}' lab-server:1.0)" ] \
  || fail "The server '$sname' is not created from the lab-server:1.0 image."
[ -n "$sip" ] && echo "$log" | grep -qwF "$sip" \
  || fail "Build #$num never addressed the server at its Terraform IP ($sip); the deploy must use the IP from terraform output."

# The app on the server: started by docker compose from /home/ec2-user, from the image this build pushed.
app=""
for c in $(docker ps -q); do
  img=$(docker inspect -f '{{.Config.Image}}' "$c")
  wd=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$c")
  case "$img" in "$REPO":*) case "$wd" in /home/ec2-user*) app=$c; break;; esac;; esac
done
[ -n "$app" ] || fail "No running $REPO container started by docker compose on the server (from /home/ec2-user)."
img=$(docker inspect -f '{{.Config.Image}}' "$app")
tag=${img##*:}
[ "$tag" != latest ] || fail "The app runs the 'latest' tag; each build needs its own tag."
tags=$(curl -s --max-time 5 http://localhost:5000/v2/java-maven-app/tags/list 2>/dev/null)
echo "$tags" | grep -q "\"$tag\"" || fail "Tag $tag is not in the registry at localhost:5000 (tags: $tags)."
echo "$log" | grep -qF "$REPO:$tag" \
  || fail "Build #$num did not push/deploy $REPO:$tag; the server is not running what the latest build produced."

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8080/)
[ "$code" = 200 ] || fail "The app does not answer on port 8080 (HTTP ${code:-none}); check its container logs."

echo "✅ PASS: build #$num pushed $REPO:$tag, Terraform (state in s3://tf-state) provisioned '$sname' ($sip), and the app is serving on :8080."
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

touch /tmp/setup-done
