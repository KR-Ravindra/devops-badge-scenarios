#!/bin/bash
# Course-faithful solution: the bootcamp's 12-terraform java-maven-app, branch
# jenkinsfile-sshagent (Jenkinsfile, server-cmds.sh, S3 backend in main.tf), changed
# only where the lab's stand-ins force it:
#  - no shared library / Docker Hub creds -> the library's buildJar/buildImage/dockerPush
#    steps inlined, no docker login;
#  - S3 backend -> same bucket block plus what MinIO needs (endpoint, path style, no STS);
#  - key pair -> public_key_location points at the lab's key;
#  - image name -> the lab registry, with the build number for a unique tag.
# Kept from the course on purpose: plain `terraform init` / `terraform apply --auto-approve`,
# `terraform output` without -raw (quoted IP), the 90 s sleep, scp/ssh with
# StrictHostKeyChecking=no, the course's region eu-central-1.
set -euxo pipefail
cd /root/java-maven-app

python3 - <<'EOF'
p = "terraform/main.tf"
s = open(p).read()
backend = '''  backend "s3" {
    bucket = "tf-state"
    key = "myapp/state.tfstate"
    region = "eu-central-1"
    endpoints = { s3 = "http://localhost:9000" }
    use_path_style = true
    skip_credentials_validation = true
    skip_requesting_account_id = true
  }
'''
s = s.replace('  required_providers {', backend + '  required_providers {', 1)
open(p, "w").write(s)
EOF
sed -i 's#/home/nana/.ssh/id_rsa.pub#/root/.ssh/server-key.pub#' terraform/variables.tf

cat > server-cmds.sh <<'EOF'
#!/usr/bin/env bash

export IMAGE=$1
docker-compose -f docker-compose.yaml up --detach
echo "success"
EOF

cat > Jenkinsfile <<'EOF'
#!/usr/bin/env groovy

pipeline {
  agent any
  tools {
    maven 'Maven'
  }
  environment {
    IMAGE_NAME = "localhost:5000/java-maven-app:java-maven-2.0-${BUILD_NUMBER}"
  }
  stages {
    stage("build app") {
      steps {
        script {
          echo 'building application jar...'
          sh 'mvn package'
        }
      }
    }
    stage("build image") {
      steps {
        script {
          echo 'building docker image...'
          sh "docker build -t ${env.IMAGE_NAME} ."
          sh "docker push ${env.IMAGE_NAME}"
        }
      }
    }
    stage("provision server") {
      environment {
        AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
        AWS_SECRET_ACCESS_KEY = credentials('jenkins-aws_secret_access_key')
        TF_VAR_env_prefix = 'test'
      }
      steps {
        script {
          dir('terraform') {
            sh "terraform init"
            sh "terraform apply --auto-approve"
            EC2_PUBLIC_IP = sh(
              script: "terraform output ec2-public_ip",
              returnStdout: true
            ).trim()
          }
        }
      }
    }
    stage("deploy") {
      steps {
        script {
          echo "waiting for EC2 server to initialize"
          sleep(time: 90, unit: "SECONDS")

          echo 'deploying docker image to EC2...'
          echo "${EC2_PUBLIC_IP}"

          def shellCmd = "bash ./server-cmds.sh ${IMAGE_NAME}"
          def ec2Instance = "ec2-user@${EC2_PUBLIC_IP}"

          sshagent(['server-ssh-key']) {
            sh "scp -o StrictHostKeyChecking=no server-cmds.sh ${ec2Instance}:/home/ec2-user"
            sh "scp -o StrictHostKeyChecking=no docker-compose.yaml ${ec2Instance}:/home/ec2-user"
            sh "ssh -o StrictHostKeyChecking=no ${ec2Instance} ${shellCmd}"
          }
        }
      }
    }
  }
}
EOF
git add -A && git commit -qm "pipeline with terraform (course style)"
