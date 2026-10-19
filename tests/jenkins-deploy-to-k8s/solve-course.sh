#!/bin/bash
# Course-faithful solution: what a candidate gets by following module 11 (EKS) of
# the bootcamp, i.e. the jenkins-jobs branch of twn-devops-bootcamp/latest/11-eks/
# java-maven-app, with only the stand-in differences changed (ECR -> localhost:5000
# without login, EKS -> k3s via a kubeconfig in the Jenkins home, no git push back,
# Service on 8080 as the task asks).
#   solve-course.sh trap  -> pipeline with the starter's Dockerfile (pods crash-loop)
#   solve-course.sh       -> also takes the course's fixed Dockerfile; check passes
set -euxo pipefail
MODE=${1:-full}
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
J=http://localhost:8080
COURSE=https://gitlab.com/twn-devops-bootcamp/latest/11-eks/java-maven-app.git
MASTER_SHA=04a40816abffed5ed9612f8fc091e26d99f48ac0
JOBS_SHA=1999257eb5088af74e473375f83f4016410c3d7b   # jenkins-jobs branch

build_and_wait() {
  local C CRUMB before
  C=$(mktemp)
  CRUMB=$(curl -sf -c $C -u admin:admin "$J/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")
  before=$(curl -sf -u admin:admin $J/job/java-maven-app/api/json | python3 -c 'import sys,json;print(json.load(sys.stdin)["nextBuildNumber"])')
  curl -sf -b $C -u admin:admin -H "$CRUMB" -X POST $J/job/java-maven-app/build
  for i in $(seq 1 60); do
    curl -sf -u admin:admin $J/job/java-maven-app/$before/api/json >/dev/null && break; sleep 2
  done
  for i in $(seq 1 180); do
    curl -sf -u admin:admin $J/job/java-maven-app/$before/api/json | grep -q '"building":false' && break; sleep 5
  done
  curl -s -u admin:admin $J/job/java-maven-app/$before/consoleText | tail -40
  curl -s -u admin:admin $J/job/java-maven-app/$before/api/json | grep -q '"result":"SUCCESS"'
}

if ! git -C /root/java-maven-app remote 2>/dev/null | grep -q origin; then
  # Lecture "configure kubectl in Jenkins": kubectl + envsubst in the container,
  # kubeconfig in the Jenkins user's ~/.kube (the k3s one: server 127.0.0.1:6443).
  docker exec jenkins sh -c 'cd /tmp && curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && mv kubectl /usr/local/bin/'
  docker exec jenkins sh -c 'apt-get update -q && apt-get install -yq gettext-base'
  docker exec jenkins mkdir -p /var/jenkins_home/.kube
  docker cp /etc/rancher/k3s/k3s.yaml jenkins:/var/jenkins_home/.kube/config

  # Throw away the starter and work from a fresh clone of the course repo
  # (Jenkins must follow the new directory).
  rm -rf /root/java-maven-app
  git clone -q $COURSE /root/java-maven-app
  cd /root/java-maven-app
  git checkout -q -B master $MASTER_SHA
  git config user.email "you@example.com"; git config user.name "You"
  git rm -q script.groovy
  git checkout $JOBS_SHA -- kubernetes
  sed -i 's/port: 80$/port: 8080/' kubernetes/service.yaml
  # The course Jenkinsfile, with ECR -> localhost:5000 (no login), AWS keys and
  # the "commit version update" stage dropped (Jenkins can't push to this repo).
  cat > Jenkinsfile <<'EOF'
#!/usr/bin/env groovy

pipeline {
    agent any
    tools {
        maven 'Maven'
    }
    environment {
        DOCKER_REPO_SERVER = 'localhost:5000'
        DOCKER_REPO = "${DOCKER_REPO_SERVER}/java-maven-app"
    }
    stages {
        stage('increment version') {
            steps {
                script {
                    echo 'incrementing app version...'
                    sh 'mvn build-helper:parse-version versions:set \
                        -DnewVersion=\\\${parsedVersion.majorVersion}.\\\${parsedVersion.minorVersion}.\\\${parsedVersion.nextIncrementalVersion} \
                        versions:commit'
                    def matcher = readFile('pom.xml') =~ '<version>(.+)</version>'
                    def version = matcher[0][1]
                    env.IMAGE_NAME = "$version-$BUILD_NUMBER"
                }
            }
        }
        stage('build app') {
            steps {
                script {
                    echo 'building the application...'
                    sh 'mvn clean package'
                }
            }
        }
        stage('build image') {
            steps {
                script {
                    echo "building the docker image..."
                    sh "docker build -t ${DOCKER_REPO}:${IMAGE_NAME} ."
                    sh "docker push ${DOCKER_REPO}:${IMAGE_NAME}"
                }
            }
        }
        stage('deploy') {
            environment {
                APP_NAME = 'java-maven-app'
            }
            steps {
                script {
                   echo 'deploying docker image...'
                   sh 'kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -'
                   sh 'envsubst < kubernetes/deployment.yaml | kubectl apply -n prod -f -'
                   sh 'envsubst < kubernetes/service.yaml | kubectl apply -n prod -f -'
                }
            }
        }
    }
}
EOF
  git add -A && git commit -qm "deploy to k8s from Jenkins"
fi

cd /root/java-maven-app
if [ "$MODE" = trap ]; then
  build_and_wait
  # Starter Dockerfile runs java-maven-app-1.0-SNAPSHOT.jar; the build makes 1.1.1.
  for i in $(seq 1 60); do
    kubectl -n prod get pods -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | grep -q '[1-9]' && break; sleep 3
  done
  kubectl -n prod get pods
  kubectl -n prod logs deploy/java-maven-app --tail=5 || true
  exit 0
fi

# The course's own fix (jenkins-jobs branch): CMD java -jar java-maven-app-*.jar
git checkout $JOBS_SHA -- Dockerfile
git commit -qam "Dockerfile: run whatever version was built" || true
build_and_wait
kubectl -n prod rollout status deploy/java-maven-app --timeout=240s
kubectl -n prod get pods,svc
