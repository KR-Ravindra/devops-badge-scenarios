#!/bin/bash
# Course-faithful solution for scenario 15: the bootcamp's 15-ansible
# java-maven-app@feature/ansible (Jenkinsfile, prepare-ansible-server.sh,
# ansible/ansible.cfg, inventory_aws_ec2.yaml, my-playbook.yaml), changed only
# where the lab's stand-ins force it:
#  - ANSIBLE_SERVER is the container name instead of a droplet IP;
#  - python3-boto3 -> python3-docker/python3-requests (Docker inventory plugin);
#  - aws_ec2 inventory -> community.docker.docker_containers (file *docker.yaml,
#    verbose_output for labels, SSH to the container's IP on network `lab`);
#    the course's tag keyed_group becomes a label keyed_group, and the plays
#    target the role=webserver group instead of `all` (the lab has a DB decoy);
#  - no "Start docker daemon" task (no systemd); ec2-user added to docker group
#    (the task asks for it).
# `solve-course.sh rerun` just runs the job again (after `check` adds ec2-3).
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

apt update
apt install ansible -y
apt install python3-docker python3-requests -y
EOF

cat > ansible/ansible.cfg <<'EOF'
[defaults]
host_key_checking = False
inventory = inventory_docker.yaml

enable_plugins = community.docker.docker_containers

remote_user = ec2-user
private_key_file = ~/ssh-key.pem
EOF

cat > ansible/inventory_docker.yaml <<'EOF'
---
plugin: community.docker.docker_containers
docker_host: unix:///var/run/docker.sock
verbose_output: true
connection_type: ssh
keyed_groups:
  - key: docker_config.Labels
    prefix: tag
compose:
  ansible_ssh_host: docker_networksettings.Networks.lab.IPAddress
  ansible_ssh_port: 22
EOF

cat > ansible/my-playbook.yaml <<'EOF'
- name: Install Docker
  hosts: tag_role_webserver
  become: yes
  tasks:
    - name: Install Docker
      yum:
        name: docker
        update_cache: yes
        state: present
    - name: Add ec2-user to docker group
      user:
        name: ec2-user
        groups: docker
        append: yes

- name: Install Docker-compose
  hosts: tag_role_webserver
  tasks:
    - name: Create docker-compose directory
      file:
        path: ~/.docker/cli-plugins
        state: directory
    - name: Get architecture of remote machine
      shell: uname -m
      register: remote_arch
    - name: Install docker-compose
      get_url:
        url: "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-{{ remote_arch.stdout }}"
        dest: ~/.docker/cli-plugins/docker-compose
        mode: +x
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
          echo "copying all neccessary files to ansible control node"
          sshagent(['ansible-server-key']) {
            sh "scp -o StrictHostKeyChecking=no ansible/* root@${ANSIBLE_SERVER}:/root"

            withCredentials([sshUserPrivateKey(credentialsId: 'ec2-server-key', keyFileVariable: 'keyfile', usernameVariable: 'user')]) {
              sh 'scp $keyfile root@$ANSIBLE_SERVER:/root/ssh-key.pem'
            }
          }
        }
      }
    }
    stage ("execute ansible playbook") {
      steps {
        script {
          echo "calling ansible playbook to configure ec2 instances"
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
git add -A && git commit -qm "ansible pipeline (course)"
build
