#!/bin/bash
# Seeds: Docker network `lab` with Jenkins (ssh-agent + ssh-steps, two SSH key
# credentials), an Ubuntu "Ansible control node" with sshd but no Ansible, two
# Amazon Linux "EC2" web servers + one database decoy (sshd, ec2-user), a starter
# app repo and a pipeline job pointing at it. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE -o pipefail

APP_REPO=https://gitlab.com/twn-devops-bootcamp/latest/15-ansible/java-maven-app.git
APP_SHA=f7b73f6e990cb87d142297d21da1ed04ab4e0215   # branch feature/ansible
JENKINS_IMAGE=jenkins/jenkins:2.568.3-lts-jdk21
UBUNTU_IMAGE=ubuntu:noble-20260911
AL_IMAGE=public.ecr.aws/amazonlinux/amazonlinux:2023.12.20260918.0
DOCKER_VERSION=29.8.2
JH=/var/lib/jenkins-lab
LAB=/opt/ansible-lab

# --- Docker. Killercoda VMs share egress IPs, so Docker Hub pulls go through mirror.gcr.io ---
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh --version $DOCKER_VERSION
fi
mkdir -p /etc/docker
python3 - <<'PY'
import json, os
p = "/etc/docker/daemon.json"
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
m = d.setdefault("registry-mirrors", [])
if "https://mirror.gcr.io" not in m:
    m.append("https://mirror.gcr.io")
json.dump(d, open(p, "w"), indent=2)
PY
systemctl restart docker 2>/dev/null || service docker restart
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info | grep -A2 -i 'registry mirrors'

pull() {  # pull with retries; fails setup if the image never arrives
  for i in 1 2 3 4 5; do docker pull -q "$1" && return 0; sleep $((i * 5)); done
  echo "could not pull $1"; return 1
}
pids=()
for img in $JENKINS_IMAGE $UBUNTU_IMAGE $AL_IMAGE; do pull $img & pids+=($!); done
for p in "${pids[@]}"; do wait $p; done

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

# --- Jenkins image: LTS + pipeline + SSH plugins (exact versions, with dependencies) ---
cat > $LAB/jenkins/plugins.txt <<'EOF'
antisamy-markup-formatter:173.v680e3a_b_69ff3
apache-httpcomponents-client-4-api:4.5.14-269.vfa_2321039a_83
asm-api:9.10.1-216.va_9256d3b_844b_
authentication-tokens:1.144.v5ff4a_5ec5c33
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
kubernetes-cli:1.375.v8001982544ba
kubernetes-client-api:7.3.1-256.v788a_0b_787114
kubernetes-credentials:207.v492f58828b_ed
mailer:534.v1b_36f5864073
mina-sshd-api-common:2.19.0-192.v2b_a_7b_2c1dc71
mina-sshd-api-core:2.19.0-192.v2b_a_7b_2c1dc71
okhttp-api:5.3.2-200.vedb_720a_cf1f8
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
cat > $LAB/jenkins/Dockerfile <<EOF
FROM $JENKINS_IMAGE
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client && rm -rf /var/lib/apt/lists/*
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF

pids=()
docker build -q -t ansible-control-lab $LAB/control & pids+=($!)
docker build -q -t ec2-lab $LAB/ec2 & pids+=($!)
docker build -q -t jenkins-ansible-lab $LAB/jenkins & pids+=($!)
for p in "${pids[@]}"; do wait $p; done

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
  crumbIssuer: "standard"
  numExecutors: 2
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: admin
          password: admin
  authorizationStrategy: loggedInUsersCanDoAnything
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
# Docker socket: it can only reach the servers over SSH. /root is mounted (not the
# repo dir itself) so the mount survives the candidate deleting/re-cloning the repo.
if ss -ltnH 'sport = :8080' | grep -q .; then
  echo "Port 8080 is already in use:"; ss -ltnp 'sport = :8080'; false
fi
docker run -d --restart=always --name jenkins --hostname jenkins --network lab -p 8080:8080 -u root \
  -v $JH:/var/jenkins_home \
  -v /root:/repos:ro \
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
J="curl -sf --max-time 10 -u admin:admin http://localhost:8080"
dip() { docker inspect -f '{{(index .NetworkSettings.Networks "lab").IPAddress}}' "$1" 2>/dev/null; }

$J/api/json >/dev/null 2>&1 || fail "Jenkins is not answering on :8080 (docker ps / docker logs jenkins)."
$J/job/java-maven-app/api/json >/dev/null 2>&1 || fail "The java-maven-app job is missing from Jenkins."
last=$($J/job/java-maven-app/lastBuild/api/json 2>/dev/null)
[ -n "$last" ] || fail "The java-maven-app job has never run."
read -r num result building ts dur < <(echo "$last" | python3 -c '
import sys,json; b=json.load(sys.stdin)
print(b["number"], b["result"], str(b["building"]).lower(), b["timestamp"]//1000, b["duration"]//1000)')
[ "$building" = false ] || fail "Build #$num is still running; wait for it to finish."
[ "$result" = SUCCESS ] || fail "The latest java-maven-app build (#$num) is not green ($result). Open its Console Output (build #$num in Jenkins) to see why."
# Strip ANSI colour codes (AnsiColor / ANSIBLE_FORCE_COLOR) before reading the log.
log=$($J/job/java-maven-app/$num/consoleText 2>/dev/null | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | tr -d '\r')
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
  echo "$recap" | grep -Eq "(^|[[:space:]])$h[[:space:]]+:" && fail "Build #$num ran the playbook against $h. Only the role=webserver servers should be in the inventory."
done
docker exec ec2-db sh -c 'command -v docker' >/dev/null 2>&1 \
  && fail "Docker got installed on ec2-db (role=database). Only the web servers should be configured."

webs=$(docker ps --filter label=role=webserver --format '{{.Names}}' | sort)
[ -n "$webs" ] || fail "No web server containers are running (docker ps)."
for h in $webs; do
  echo "$recap" | grep -Eq "(^|[[:space:]])$h[[:space:]]+:.*unreachable=0[[:space:]]+failed=0" \
    || fail "Build #$num's PLAY RECAP has no clean (unreachable=0 failed=0) line for $h. Open the Console Output of #$num."
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

# --- self-test: what the candidate relies on ---
docker --version
for c in jenkins ansible-server ec2-1 ec2-2 ec2-db; do
  [ "$(docker inspect -f '{{.State.Running}}' $c)" = true ]
done
chmod 600 $LAB/keys/ansible-server-key $LAB/keys/ec2-server-key
SSHO="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
aip=$(docker inspect -f '{{(index .NetworkSettings.Networks "lab").IPAddress}}' ansible-server)
for i in $(seq 1 20); do ssh $SSHO -i $LAB/keys/ansible-server-key root@$aip true && break; sleep 2; done
ssh $SSHO -i $LAB/keys/ansible-server-key root@$aip 'python3 --version; ! command -v ansible'
for h in ec2-1 ec2-2; do
  ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "lab").IPAddress}}' $h)
  for i in $(seq 1 20); do ssh $SSHO -i $LAB/keys/ec2-server-key ec2-user@$ip true && break; sleep 2; done
  ssh $SSHO -i $LAB/keys/ec2-server-key ec2-user@$ip 'sudo -n true'
done
docker exec jenkins getent hosts ansible-server
curl -sf -o /dev/null http://localhost:8080/login
curl -sf -o /dev/null -u admin:admin http://localhost:8080/crumbIssuer/api/json
# every pinned plugin loaded (a broken dependency would hide steps like sshagent)
curl -sfg -u admin:admin 'http://localhost:8080/pluginManager/api/json?depth=1&tree=plugins[shortName,version,active]' \
  | python3 -c '
import sys, json
ps = {p["shortName"]: p for p in json.load(sys.stdin)["plugins"]}
want = [l.split(":")[0] for l in open("/opt/ansible-lab/jenkins/plugins.txt") if l.strip()]
bad = [n for n in want if not ps.get(n, {}).get("active")]
print("plugins loaded:", len(ps), "not active:", bad)
sys.exit(1 if bad else 0)'
test -d /root/java-maven-app/.git
check | grep -q 'NOT YET'

touch /tmp/setup-done
