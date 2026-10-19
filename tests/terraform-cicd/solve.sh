#!/bin/bash
# Reference solution for scenario 14, used by CI to prove setup + check work.
set -euxo pipefail
cd /root/java-maven-app

# 1) Terraform: remote state in the S3 (MinIO) bucket; the lab's public key, not a laptop path.
cat > terraform/backend.tf <<'EOF'
terraform {
  backend "s3" {
    bucket                      = "tf-state"
    key                         = "myapp/state.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://localhost:9000" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
EOF
echo 'public_key_location = "/root/.ssh/server-key.pub"' > terraform/terraform.tfvars

# 2) server-cmds.sh: no Docker Hub login needed for the lab registry; IMAGE comes from $1.
cat > server-cmds.sh <<'EOF'
#!/usr/bin/env bash
export IMAGE=$1
docker-compose -f docker-compose.yaml up --detach
echo "success"
EOF

# 3) Jenkinsfile (the course pipeline, adapted to the lab stand-ins).
cat > Jenkinsfile <<'EOF'
pipeline {
  agent any
  tools { maven 'Maven' }
  environment {
    IMAGE_NAME = "localhost:5000/java-maven-app:1.0-${BUILD_NUMBER}"
  }
  stages {
    stage('build app') {
      steps { sh 'mvn -B package' }
    }
    stage('build image') {
      steps {
        sh 'docker build -t $IMAGE_NAME .'
        sh 'docker push $IMAGE_NAME'
      }
    }
    stage('provision server') {
      environment {
        AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
        AWS_SECRET_ACCESS_KEY = credentials('jenkins-aws_secret_access_key')
        TF_VAR_env_prefix = 'test'
      }
      steps {
        script {
          dir('terraform') {
            sh 'terraform init -input=false'
            sh 'terraform apply -auto-approve -input=false'
            EC2_PUBLIC_IP = sh(script: 'terraform output -raw ec2-public_ip', returnStdout: true).trim()
          }
        }
      }
    }
    stage('deploy') {
      steps {
        script {
          echo "deploying ${IMAGE_NAME} to ${EC2_PUBLIC_IP}"
          def ssh_opts = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
          def ec2Instance = "ec2-user@${EC2_PUBLIC_IP}"
          sshagent(['server-ssh-key']) {
            sh "for i in \$(seq 1 20); do ssh ${ssh_opts} ${ec2Instance} true && break; sleep 3; done"
            sh "scp ${ssh_opts} server-cmds.sh docker-compose.yaml ${ec2Instance}:/home/ec2-user"
            sh "ssh ${ssh_opts} ${ec2Instance} bash ./server-cmds.sh ${IMAGE_NAME}"
          }
        }
      }
    }
  }
}
EOF
git add -A && git commit -qm "pipeline with terraform"
