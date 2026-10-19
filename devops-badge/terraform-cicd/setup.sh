#!/bin/bash
# Seeds: registry:2 on :5000 (Docker Hub/ECR stand-in), MinIO on :9000/:9001 with bucket
# tf-state (S3 stand-in), a pre-built "lab-server" image that Terraform's docker
# provider turns into the "EC2" server, an SSH key pair, Jenkins in Docker (:8081)
# with Maven + docker CLI + terraform + ssh-agent and the course credentials, a
# starter repo (course code minus Jenkinsfile and Terraform solution) and a
# pipeline job pointing at it. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE
set -o pipefail
rm -f /tmp/setup-done /tmp/setup-failed

APP_REPO=https://gitlab.com/twn-devops-bootcamp/latest/12-terraform/java-maven-app.git
APP_SHA=660fa3b392e4513e6afcba7fe2394e23f1b1b60b   # branch jenkinsfile-sshagent
DOCKER_VERSION=28.5.1
JENKINS_IMAGE=jenkins/jenkins:2.568.3-lts-jdk21
MAVEN_IMAGE=maven:3.9.11-eclipse-temurin-17
DOCKER_CLI_IMAGE=docker:27.5.1-cli
TERRAFORM_IMAGE=hashicorp/terraform:1.16.3
TF_DOCKER_PROVIDER=3.6.2
MINIO_IMAGE=bitnamilegacy/minio:2025.7.23-debian-12-r5
# This MinIO build has no web console; Bitnami ships MinIO's console separately.
MINIO_CONSOLE_IMAGE=bitnamilegacy/minio-object-browser:2.0.2-debian-12-r4
REGISTRY_IMAGE=registry:2.8.3
UBUNTU_IMAGE=ubuntu:24.04
# Used unpinned by the course's Dockerfile / docker-compose.yaml; pre-pulled so builds don't hit Docker Hub.
APP_BASE_IMAGES="amazoncorretto:17-alpine-jdk postgres:16"
S3_KEY=labadmin
S3_SECRET=labsecret123
JH=/var/lib/jenkins-lab
PORTS="5000 5432 8080 8081 9000 9001"

# --- Docker (pinned), pulling through mirror.gcr.io to dodge Docker Hub rate limits ---
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh --version $DOCKER_VERSION
fi
mkdir -p /etc/docker
python3 - <<'EOF'
import json, os
p = "/etc/docker/daemon.json"
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
m = d.setdefault("registry-mirrors", [])
if "https://mirror.gcr.io" not in m:
    m.append("https://mirror.gcr.io")
json.dump(d, open(p, "w"), indent=2)
EOF
systemctl restart docker 2>/dev/null || service docker restart
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info | grep -A1 'Registry Mirrors'

pull() {
  for i in 1 2 3 4 5; do docker pull -q "$1" >/dev/null && return 0; sleep $((i * 5)); done
  echo "PULL FAILED: $1"; return 1
}
pids=()
for img in $JENKINS_IMAGE $MAVEN_IMAGE $DOCKER_CLI_IMAGE $TERRAFORM_IMAGE $MINIO_IMAGE $MINIO_CONSOLE_IMAGE $REGISTRY_IMAGE \
           $UBUNTU_IMAGE $APP_BASE_IMAGES; do
  pull "$img" & pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

# --- Old lab leftovers, then make sure the ports the lab needs are free ---
docker rm -f registry minio minio-console jenkins 2>/dev/null || true
docker ps -aq --filter ancestor=lab-server:1.0 | xargs -r docker rm -f
docker ps -aq --filter label=com.docker.compose.project | xargs -r docker rm -f
for p in $PORTS; do
  if ss -ltnH "sport = :$p" | grep -q .; then
    echo "PORT $p IS ALREADY IN USE:"; ss -ltnp "sport = :$p"; false
  fi
done

# --- Registry (Docker Hub / ECR stand-in) ---
docker run -d --restart=always --name registry -p 5000:5000 $REGISTRY_IMAGE

# --- MinIO (S3 stand-in) with the state bucket, and its web console on :9001 ---
docker run -d --restart=always --name minio -p 9000:9000 \
  -e MINIO_ROOT_USER=$S3_KEY -e MINIO_ROOT_PASSWORD=$S3_SECRET -e MINIO_DEFAULT_BUCKETS=tf-state \
  $MINIO_IMAGE
docker run -d --restart=always --name minio-console --network host \
  -e CONSOLE_MINIO_SERVER=http://localhost:9000 \
  $MINIO_CONSOLE_IMAGE server --port 9001

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
FROM $UBUNTU_IMAGE
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

# --- Jenkins image: LTS + pinned plugins + Maven + docker CLI + terraform (provider pre-cached) ---
mkdir -p /opt/jenkins-lab
# Resolved for core 2.568.3 (workflow-aggregator git credentials-binding plain-credentials
# ssh-credentials ssh-agent configuration-as-code + dependencies), all released by 2026-10-04.
cat > /opt/jenkins-lab/plugins.txt <<'EOF'
antisamy-markup-formatter:173.v680e3a_b_69ff3
apache-httpcomponents-client-4-api:4.5.14-269.vfa_2321039a_83
asm-api:9.10.1-216.va_9256d3b_844b_
bootstrap5-api:5.3.8-1048.va_c299057e35c
bouncycastle-api:2.30.1.85.2-304.v4b_5b_62e59a_a_7
branch-api:2.1303.v9f3b_95dc329d
caffeine-api:3.2.4-208.v7e2da_a_7db_82b_
cloudbees-folder:6.1106.v3a_d9a_6d2465e
commons-lang3-api:3.20.0-109.ve43756e2d2b_4
commons-text-api:1.15.0-218.va_61573470393
configuration-as-code:2132.v60435f73c18a_
credentials:1511.v2e3cb_0008ef0
credentials-binding:728.v902a_273b_8947
display-url-api:2.217.va_6b_de84cc74b_
durable-task:686.v80ff80875b_82
font-awesome-api:7.3.1-1013.v0835a_879ec6d
git:5.10.1
git-client:6.6.1
gson-api:2.14.0-201.v8eefe5515533
instance-identity:203.v15e81a_1b_7a_38
ionicons-api:94.vcc3065403257
jackson-annotations2-api:2.22-19.v10a_a_582ea_26e
jackson2-api:2.22.2-445.vdc613f1d8012
jakarta-activation-api:2.1.4-1
jakarta-mail-api:2.1.5-1
jakarta-xml-bind-api:4.0.9-19.v2b_a_5b_44d9a_1c
javax-activation-api:1.2.0-8
jaxb:2.3.9-143.v5979df3304e6
joda-time-api:2.15.0-208.v6b_084e7a_d9f0
json-api:20260814-226.v20f9685d642c
mailer:534.v1b_36f5864073
mina-sshd-api-common:2.19.0-192.v2b_a_7b_2c1dc71
mina-sshd-api-core:2.19.0-192.v2b_a_7b_2c1dc71
pipeline-build-step:601.v6d4c6d1a_9dc7
pipeline-groovy-lib:806.v408277b_33d1d
pipeline-input-step:560.v56198a_642157
pipeline-milestone-step:152.v6e22b_8cfc66c
pipeline-model-api:2.2293.v6e7193cec599
pipeline-model-definition:2.2293.v6e7193cec599
pipeline-model-extensions:2.2293.v6e7193cec599
pipeline-stage-step:345.va_96187909426
pipeline-stage-tags-metadata:2.2293.v6e7193cec599
plain-credentials:199.v9f8e1f741799
plugin-util-api:7.1341.v039f146993d9
prism-api:1.30.0-741.v034eb_0b_0a_a_fa_
scm-api:728.vc30dcf7a_0df5
script-security:1429.v0810f1b_530f5
snakeyaml-api:2.5-149.v72471e9c6371
ssh-agent:433.v9e73d67c3f74
ssh-credentials:372.va_250881b_08cd
structs:362.va_b_695ef4fdf9
variant:70.va_d9f17f859e0
woodstox-core-api:7.2.2-10.vcb_629759b_2c2
workflow-aggregator:608.v67378e9d3db_1
workflow-api:1413.v2ff1a_5e720fa_
workflow-basic-steps:1098.v808b_fd7f8cf4
workflow-cps:4383.v04fa_a_3d67b_d9
workflow-durable-task-step:1479.v56e587f413a_7
workflow-job:1602.v2a_70b_80a_2396
workflow-multibranch:842.v3a_b_59b_57b_e6e
workflow-scm-step:487.v41313a_96b_65d
workflow-step-api:724.v538c2362b_dfb_
workflow-support:1015.v785e5a_b_b_8b_22
EOF
cat > /opt/jenkins-lab/Dockerfile <<EOF
FROM $DOCKER_CLI_IMAGE AS dockercli
FROM $MAVEN_IMAGE AS mvn
FROM $TERRAFORM_IMAGE AS tf
FROM $JENKINS_IMAGE
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client && rm -rf /var/lib/apt/lists/* \\
 && git config --system --add safe.directory '*'
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=mvn /usr/share/maven /usr/share/maven
COPY --from=tf /bin/terraform /usr/local/bin/terraform
ENV TF_PLUGIN_CACHE_DIR=/opt/tf-plugin-cache TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1 TF_IN_AUTOMATION=1
RUN ln -s /usr/share/maven/bin/mvn /usr/local/bin/mvn
RUN mkdir -p /opt/tf-plugin-cache /tmp/tfwarm \\
 && printf 'terraform {\\n  required_providers {\\n    docker = { source = "kreuzwerker/docker", version = "$TF_DOCKER_PROVIDER" }\\n  }\\n}\\n' > /tmp/tfwarm/main.tf \\
 && cd /tmp/tfwarm && terraform init -backend=false -input=false && rm -rf /tmp/tfwarm
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \\
 && (jenkins-plugin-cli --list 2>&1 | tail -80 || true)
# Maven's default heap is 1/4 of RAM; cap it so the build fits next to Jenkins, the app and MinIO.
ENV MAVEN_OPTS="-Xmx512m"
ENV JAVA_OPTS="-Xmx768m -Djenkins.install.runSetupWizard=false -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF
docker build --progress=plain -t jenkins-lab /opt/jenkins-lab 2>&1 | tail -90
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
# No unclassified.location.url: Jenkins derives links from the request, so they stay on
# the lab's proxy hostname.
cat > $JH/casc.yaml <<EOF
jenkins:
  crumbIssuer: "standard"
  numExecutors: 2
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: admin
          password: admin
  authorizationStrategy: loggedInUsersCanDoAnything
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
# host does. Port 8081 because the app takes 8080 (docker-compose.yaml). The server's
# public key is mounted at the same path, so Terraform in Jenkins can read it.
docker run -d --restart=always --name jenkins --network host -u root \
  -e JENKINS_OPTS=--httpPort=8081 \
  -v $JH:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /root/java-maven-app:/repos/java-maven-app:ro \
  -v /root/.ssh/server-key.pub:/root/.ssh/server-key.pub:ro \
  jenkins-lab
for i in $(seq 1 100); do
  curl -sf -u admin:admin http://localhost:8081/job/java-maven-app/api/json >/dev/null 2>&1 && break; sleep 3
done
docker logs --tail 30 jenkins

# MinIO must be up with the bucket before we call it ready.
for i in $(seq 1 30); do
  docker exec -e MC_HOST_l=http://$S3_KEY:$S3_SECRET@localhost:9000 minio mc ls l/tf-state >/dev/null 2>&1 && break; sleep 2
done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/bin/bash
# Pass when the latest Jenkins build is green, its Terraform state lives in the MinIO
# bucket and holds the server, and the server runs (via compose) the exact image that
# build pushed, answering on :8080.
fail() { echo "❌ NOT YET: $1"; exit 0; }
J="curl -sf --max-time 10 -u admin:admin http://localhost:8081"
REPO=localhost:5000/java-maven-app
MC="docker exec -e MC_HOST_l=http://labadmin:labsecret123@localhost:9000 minio mc"

# Lab-server containers the state might not know about (left from earlier runs).
strays() {
  docker ps -a --filter ancestor=lab-server:1.0 --format '{{.Names}}' | grep -vxF "${1:-}" | paste -sd, -
}

$J/api/json >/dev/null 2>&1 || fail "Jenkins is not answering on :8081 (docker ps / docker logs jenkins)."
last=$($J/job/java-maven-app/lastBuild/api/json 2>/dev/null) || fail "The java-maven-app job has never run."
num=$(echo "$last" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
log=$($J/job/java-maven-app/$num/consoleText 2>/dev/null | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')
echo "$last" | grep -q '"building":true' && fail "Build #$num is still running; wait for it to finish."
if ! echo "$last" | grep -q '"result":"SUCCESS"'; then
  if echo "$log" | grep -q 'is already in use by container'; then
    fail "Build #$num is not green: Terraform tried to create a server whose container name is already taken by a container its state doesn't track ($(strays)). Container names are unique on this machine."
  fi
  fail "The latest java-maven-app build (#$num) is not green."
fi

# Terraform state must be in the S3 (MinIO) bucket and contain the server.
$MC ls l/tf-state >/dev/null 2>&1 || fail "MinIO (S3 stand-in) is not answering on :9000 or bucket tf-state is missing (docker logs minio)."
objs=$($MC ls -r --json l/tf-state 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    try: o = json.loads(line)
    except Exception: continue
    if o.get("type") == "file": print(o["key"])' 2>/dev/null)
s=$(strays)
[ -n "$objs" ] || fail "No Terraform state in the S3 bucket tf-state (is the pipeline using the S3 backend?).${s:+ Server containers not tracked by it: $s.}"
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
[ -n "$srv" ] || fail "The state in bucket tf-state does not contain the server (a docker_container resource).${s:+ Server containers not tracked by it: $s.}"
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
tags=$(curl -sf --max-time 5 http://localhost:5000/v2/java-maven-app/tags/list 2>/dev/null) \
  || fail "The registry at localhost:5000 is not answering (docker ps / docker logs registry)."
echo "$tags" | grep -q "\"$tag\"" || fail "Tag $tag is not in the registry at localhost:5000 (tags: $tags)."
# The build's log must name the image it pushed: either the full name, or docker push's
# "<tag>: digest:" line for this repository.
echo "$log" | grep -qF "$REPO:$tag" \
  || { echo "$log" | grep -qF "$REPO" && echo "$log" | grep -qF "$tag: digest:"; } \
  || fail "Build #$num did not push/deploy $REPO:$tag; the server is not running what the latest build produced."

curl -sf -o /dev/null --max-time 5 http://localhost:8080/ \
  || fail "The app container is running but nothing answers HTTP 200 on port 8080; check its logs (docker logs $(docker inspect -f '{{.Name}}' "$app" | tr -d /))."

echo "✅ PASS: build #$num pushed $REPO:$tag, Terraform (state in s3://tf-state) provisioned '$sname' ($sip), and the app is serving on :8080."
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

# --- Self-test: everything the candidate relies on ---
curl -sf -u admin:admin http://localhost:8081/job/java-maven-app/api/json >/dev/null
curl -sf -o /dev/null http://localhost:8081/login
curl -sf -u admin:admin http://localhost:8081/credentials/store/system/domain/_/credential/server-ssh-key/api/json >/dev/null
docker exec jenkins terraform version
docker exec jenkins mvn -v
docker exec jenkins docker version --format '{{.Server.Version}}'
docker exec jenkins test -r /root/.ssh/server-key.pub
docker exec jenkins sh -c 'echo "$MAVEN_OPTS"' | grep -q Xmx512m
docker exec -e MC_HOST_l=http://$S3_KEY:$S3_SECRET@localhost:9000 minio mc ls l/tf-state
for i in $(seq 1 30); do curl -sf -o /dev/null http://localhost:9001/ && break; sleep 2; done
curl -sf -o /dev/null http://localhost:9001/ || { docker logs --tail 30 minio-console || true; false; }
curl -sf http://localhost:5000/v2/ >/dev/null
docker image inspect lab-server:1.0 >/dev/null
check | grep -q 'NOT YET'

touch /tmp/setup-done
