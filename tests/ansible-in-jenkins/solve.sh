#!/bin/bash
# Reference solution for scenario 15, used by CI to prove setup + check work.
# `solve.sh`        commits the pipeline + Ansible files and runs the job.
# `solve.sh rerun`  just runs the job again (after `check` adds ec2-3).
set -euxo pipefail
J=http://localhost:8080

build() {
  C=$(mktemp); CRUMB=$(curl -sf -c $C -u admin:admin "$J/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")
  before=$(curl -s -u admin:admin $J/job/java-maven-app/api/json | python3 -c 'import sys,json;b=json.load(sys.stdin)["lastBuild"];print(b["number"] if b else 0)')
  curl -sf -b $C -u admin:admin -H "$CRUMB" -X POST $J/job/java-maven-app/build
  for i in $(seq 1 120); do
    s=$(curl -s -u admin:admin $J/job/java-maven-app/lastBuild/api/json || true)
    n=$(echo "$s" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])' 2>/dev/null || echo 0)
    [ "$n" -gt "$before" ] && echo "$s" | grep -q '"building":false' && break; sleep 5
  done
  curl -s -u admin:admin $J/job/java-maven-app/lastBuild/consoleText | tail -60
}

if [ "${1:-}" = rerun ]; then build; exit 0; fi

cd /root/java-maven-app
mkdir -p ansible
cat > prepare-ansible-server.sh <<'EOF'
#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q ansible python3-docker
chmod 600 /root/ssh-key.pem
EOF
cat > ansible/ansible.cfg <<'EOF'
[defaults]
host_key_checking = False
inventory = inventory_docker.yaml
enable_plugins = community.docker.docker_containers
remote_user = ec2-user
private_key_file = ~/ssh-key.pem
EOF
# Analog of inventory_aws_ec2.yaml: hosts come from the Docker API, grouped by the role label.
cat > ansible/inventory_docker.yaml <<'EOF'
plugin: community.docker.docker_containers
docker_host: unix:///var/run/docker.sock
connection_type: ssh
verbose_output: true
keyed_groups:
  - key: docker_config.Labels.role
    prefix: role
compose:
  ansible_ssh_host: docker_networksettings.Networks.lab.IPAddress
  ansible_ssh_port: 22
EOF
cat > ansible/my-playbook.yaml <<'EOF'
- name: Install Docker
  hosts: role_webserver
  become: yes
  tasks:
    - name: Install Docker
      dnf:
        name: docker
        state: present
    - name: Add ec2-user to docker group
      user:
        name: ec2-user
        groups: docker
        append: yes

- name: Install Docker Compose
  hosts: role_webserver
  tasks:
    - name: Create cli-plugins directory
      file:
        path: ~/.docker/cli-plugins
        state: directory
    - name: Get architecture of remote machine
      shell: uname -m
      register: remote_arch
      changed_when: false
    - name: Install docker compose plugin
      get_url:
        url: "https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-linux-{{ remote_arch.stdout }}"
        dest: ~/.docker/cli-plugins/docker-compose
        mode: "0755"
EOF
cat > Jenkinsfile <<'EOF'
pipeline {
  agent any
  environment {
    ANSIBLE_SERVER = "ansible-server"
  }
  stages {
    stage("copy files to ansible server") {
      steps {
        script {
          sshagent(['ansible-server-key']) {
            sh "scp -o StrictHostKeyChecking=no ansible/* root@${ANSIBLE_SERVER}:/root"
            withCredentials([sshUserPrivateKey(credentialsId: 'ec2-server-key', keyFileVariable: 'keyfile', usernameVariable: 'user')]) {
              sh 'scp -o StrictHostKeyChecking=no $keyfile root@$ANSIBLE_SERVER:/root/ssh-key.pem'
            }
          }
        }
      }
    }
    stage("execute ansible playbook") {
      steps {
        script {
          def remote = [:]
          remote.name = "ansible-server"
          remote.host = ANSIBLE_SERVER
          remote.allowAnyHosts = true
          withCredentials([sshUserPrivateKey(credentialsId: 'ansible-server-key', keyFileVariable: 'keyfile', usernameVariable: 'user')]) {
            remote.user = user
            remote.identityFile = keyfile
            sshScript remote: remote, script: "prepare-ansible-server.sh"
            sshCommand remote: remote, command: "ansible-playbook my-playbook.yaml"
          }
        }
      }
    }
  }
}
EOF
git add -A && git commit -qm "ansible pipeline"
build
