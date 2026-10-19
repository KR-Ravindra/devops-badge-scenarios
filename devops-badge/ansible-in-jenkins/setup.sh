#!/bin/bash
# Seeds: Docker network `lab` with Jenkins (ssh-agent + ssh-steps, two SSH key
# credentials), an Ubuntu "Ansible control node" with sshd but no Ansible, two
# Amazon Linux "EC2" web servers + one database decoy (sshd, ec2-user), a starter
# app repo and a pipeline job pointing at it. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE

APP_REPO=https://gitlab.com/twn-devops-bootcamp/latest/15-ansible/java-maven-app.git
APP_SHA=f7b73f6e990cb87d142297d21da1ed04ab4e0215   # branch feature/ansible
JENKINS_IMAGE=jenkins/jenkins:2.568.3-lts-jdk21
UBUNTU_IMAGE=ubuntu:noble-20260911
AL_IMAGE=amazonlinux:2023.12.20260918.0
JH=/var/lib/jenkins-lab
LAB=/opt/ansible-lab

# --- Docker ---
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done

docker rm -f jenkins ansible-server ec2-1 ec2-2 ec2-3 ec2-db 2>/dev/null || true
docker network rm lab 2>/dev/null || true
docker network create lab

# --- SSH keys: one for the control node (root), one for the "EC2" servers (ec2-user).
# RSA/PEM so every Jenkins SSH plugin can read them.
rm -rf $LAB; mkdir -p $LAB/keys $LAB/control $LAB/ec2 $LAB/jenkins
ssh-keygen -q -t rsa -b 3072 -m PEM -N '' -C ansible-server-key -f $LAB/keys/ansible-server-key
ssh-keygen -q -t rsa -b 3072 -m PEM -N '' -C ec2-server-key -f $LAB/keys/ec2-server-key
cp $LAB/keys/ansible-server-key.pub $LAB/control/authorized_keys
cp $LAB/keys/ec2-server-key.pub $LAB/ec2/authorized_keys

# --- Control node image: sshd + python3, no Ansible ---
cat > $LAB/control/Dockerfile <<EOF
FROM $UBUNTU_IMAGE
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh
COPY authorized_keys /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys && ssh-keygen -A
CMD ["/usr/sbin/sshd", "-D", "-e"]
EOF

# --- "EC2" image: Amazon Linux 2023, sshd, ec2-user with passwordless sudo ---
cat > $LAB/ec2/Dockerfile <<EOF
FROM $AL_IMAGE
RUN dnf install -y openssh-server sudo shadow-utils util-linux procps-ng tar gzip \
 && dnf clean all \
 && useradd -m ec2-user && usermod -p '*' ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh && ssh-keygen -A
COPY authorized_keys /home/ec2-user/.ssh/authorized_keys
RUN chown -R ec2-user:ec2-user /home/ec2-user/.ssh && chmod 700 /home/ec2-user/.ssh \
 && chmod 600 /home/ec2-user/.ssh/authorized_keys
CMD ["/usr/sbin/sshd", "-D", "-e"]
EOF

# --- Jenkins image: LTS + pipeline + SSH plugins ---
cat > $LAB/jenkins/Dockerfile <<EOF
FROM $JENKINS_IMAGE
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client && rm -rf /var/lib/apt/lists/* \
 && jenkins-plugin-cli --plugins workflow-aggregator git credentials-binding ssh-credentials ssh-agent ssh-steps configuration-as-code
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF

docker build -q -t ansible-control-lab $LAB/control &
p1=$!
docker build -q -t ec2-lab $LAB/ec2 &
p2=$!
docker build -q -t jenkins-ansible-lab $LAB/jenkins &
p3=$!
wait $p1; wait $p2; wait $p3

# --- Servers. Launching is a script so `check` can add a web server later. ---
cat > /usr/local/bin/badge-launch-ec2 <<'EOF'
#!/bin/bash
# usage: badge-launch-ec2 <name> <role>
docker rm -f "$1" >/dev/null 2>&1 || true
docker run -d --restart=always --name "$1" --hostname "$1" --network lab \
  --label role="$2" --label lab=ansible-in-jenkins ec2-lab >/dev/null
EOF
chmod +x /usr/local/bin/badge-launch-ec2
badge-launch-ec2 ec2-1 webserver
badge-launch-ec2 ec2-2 webserver
badge-launch-ec2 ec2-db database

docker run -d --restart=always --name ansible-server --hostname ansible-server --network lab \
  -v /var/run/docker.sock:/var/run/docker.sock ansible-control-lab

# --- Starter app repo (course code, without the pipeline and Ansible files) ---
rm -rf /root/java-maven-app
git clone -q -b feature/ansible "$APP_REPO" /root/java-maven-app
cd /root/java-maven-app
git checkout -q "$APP_SHA"
rm -rf .git Jenkinsfile script.groovy prepare-ansible-server.sh ansible
git init -q -b master
git config user.email "you@example.com"; git config user.name "You"
git add -A && git commit -qm "starting code"
git config --global --add safe.directory /root/java-maven-app
cd /

# --- Jenkins home: JCasC (admin/admin, both SSH credentials) + the pipeline job ---
rm -rf $JH; mkdir -p $JH/jobs/java-maven-app $JH/keys
cp $LAB/keys/ansible-server-key $LAB/keys/ec2-server-key $JH/keys/
cat > $JH/casc.yaml <<'EOF'
jenkins:
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: true
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
    url: http://localhost:8080/
credentials:
  system:
    domainCredentials:
      - credentials:
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: ansible-server-key
              username: root
              description: Ansible control node (root)
              privateKeySource:
                directEntry:
                  privateKey: "${readFile:/var/jenkins_home/keys/ansible-server-key}"
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: ec2-server-key
              username: ec2-user
              description: EC2 servers key pair (ec2-user)
              privateKeySource:
                directEntry:
                  privateKey: "${readFile:/var/jenkins_home/keys/ec2-server-key}"
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

# Jenkins sits on the lab network (reaches ansible-server by name) but has no
# Docker socket: it can only reach the servers over SSH.
docker run -d --restart=always --name jenkins --hostname jenkins --network lab -p 8080:8080 -u root \
  -v $JH:/var/jenkins_home \
  -v /root/java-maven-app:/repos/java-maven-app:ro \
  jenkins-ansible-lab
for i in $(seq 1 90); do
  curl -sf -u admin:admin http://localhost:8080/job/java-maven-app/api/json >/dev/null 2>&1 && break; sleep 3
done
curl -sf -u admin:admin http://localhost:8080/job/java-maven-app/api/json >/dev/null
for c in ansible-server-key ec2-server-key; do
  curl -sf -u admin:admin http://localhost:8080/credentials/store/system/domain/_/credential/$c/api/json >/dev/null
done
docker exec jenkins git config --global --add safe.directory /repos/java-maven-app

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/bin/bash
# Pass when the latest Jenkins build is green, SSHed into ansible-server, which
# has Ansible (Jenkins doesn't), and during that build ansible-server SSHed into
# every role=webserver container as ec2-user, which now has docker + compose +
# docker group. Once ec2-1/ec2-2 are done, adds web server ec2-3 (scale-out) and
# requires a re-run that picks it up without changes.
fail() { echo "❌ NOT YET: $1"; exit 0; }
J="curl -s --max-time 10 -u admin:admin http://localhost:8080"
dip() { docker inspect -f '{{(index .NetworkSettings.Networks "lab").IPAddress}}' "$1" 2>/dev/null; }

$J/api/json >/dev/null 2>&1 || fail "Jenkins is not answering on :8080 (docker ps / docker logs jenkins)."
last=$($J/job/java-maven-app/lastBuild/api/json -f 2>/dev/null)
[ -n "$last" ] || fail "The java-maven-app job has never run."
read -r num result building ts dur < <(echo "$last" | python3 -c '
import sys,json; b=json.load(sys.stdin)
print(b["number"], b["result"], str(b["building"]).lower(), b["timestamp"]//1000, b["duration"]//1000)')
[ "$building" = false ] || fail "Build #$num is still running; wait for it to finish."
[ "$result" = SUCCESS ] || fail "The latest java-maven-app build (#$num) is not green."
log=$($J/job/java-maven-app/$num/consoleText 2>/dev/null)
since=$((ts - 1)); until=$((ts + dur + 2))

docker exec jenkins sh -c 'command -v ansible-playbook || command -v ansible' >/dev/null 2>&1 \
  && fail "Ansible is installed in the Jenkins container. Jenkins must hand the work to ansible-server, not run Ansible itself."
docker exec ansible-server sh -c 'command -v ansible-playbook' >/dev/null 2>&1 \
  || fail "Ansible is not installed on ansible-server. Preparing the control node is part of the pipeline."

jip=$(dip jenkins); aip=$(dip ansible-server)
docker logs --since "$since" --until "$until" ansible-server 2>&1 | grep -q "Accepted publickey for root from $jip " \
  || fail "Build #$num never logged in to ansible-server over SSH (as root, from Jenkins)."
echo "$log" | grep -q 'PLAY RECAP' || fail "Build #$num did not run an Ansible playbook (no PLAY RECAP in its console output)."

recap=$(echo "$log" | sed -n '/PLAY RECAP/,$p')
for h in ansible-server jenkins ec2-db; do
  echo "$recap" | grep -Eq "^$h[[:space:]]+:" && fail "Build #$num ran the playbook against $h. Only the role=webserver servers should be in the inventory."
done
docker exec ec2-db sh -c 'command -v docker' >/dev/null 2>&1 \
  && fail "Docker got installed on ec2-db (role=database). Only the web servers should be configured."

webs=$(docker ps --filter label=role=webserver --format '{{.Names}}' | sort)
[ -n "$webs" ] || fail "No web server containers are running (docker ps)."
for h in $webs; do
  echo "$recap" | grep -Eq "^$h[[:space:]]+:.*unreachable=0[[:space:]]+failed=0" \
    || fail "Build #$num's PLAY RECAP has no clean (unreachable=0 failed=0) line for $h."
  # Ansible's ControlPersist may reuse an SSH session from an earlier run, so
  # require one SSH login ever and no docker exec/API connection during this build.
  docker logs "$h" 2>&1 | grep -q "Accepted publickey for ec2-user from $aip " \
    || fail "ansible-server has never connected to $h over SSH as ec2-user."
  timeout 30 docker events --since "$since" --until "$until" --filter type=container --filter container="$h" \
    --format '{{.Action}}' 2>/dev/null | grep -q '^exec_' \
    && fail "During build #$num, $h was reached through docker exec / the Docker API, not over SSH."
  docker exec "$h" su - ec2-user -c 'docker --version' >/dev/null 2>&1 \
    || fail "On $h, 'docker --version' does not work for ec2-user."
  docker exec "$h" su - ec2-user -c 'docker compose version' >/dev/null 2>&1 \
    || fail "On $h, 'docker compose version' does not work for ec2-user."
  docker exec "$h" id -nG ec2-user | grep -qw docker \
    || fail "On $h, ec2-user is not in the docker group."
done

if ! docker inspect ec2-3 >/dev/null 2>&1; then
  badge-launch-ec2 ec2-3 webserver
  fail "ec2-1 and ec2-2 are configured. A new web server, ec2-3 (role=webserver), has just been launched. Run the job again, without changing anything, and it must configure ec2-3 too."
fi

echo "✅ PASS: build #$num ran Ansible on ansible-server, which configured $(echo $webs | tr ' ' ',') over SSH with docker + compose + docker group."
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

touch /tmp/setup-done
