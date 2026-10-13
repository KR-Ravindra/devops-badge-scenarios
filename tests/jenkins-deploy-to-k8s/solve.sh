#!/bin/bash
# Reference solution for scenario 11, used by CI to prove setup + check work.
set -euxo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
J=http://localhost:8080

# 1) kubectl inside the Jenkins container (the lecture's "install kubectl on Jenkins").
docker exec jenkins sh -c 'curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x /usr/local/bin/kubectl'

# 2) Least-privilege ServiceAccount for Jenkins in prod, kubeconfig stored as a Jenkins credential.
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
kubectl -n prod create serviceaccount jenkins --dry-run=client -o yaml | kubectl apply -f -
kubectl -n prod create rolebinding jenkins-edit --clusterrole=edit --serviceaccount=prod:jenkins --dry-run=client -o yaml | kubectl apply -f -
TOKEN=$(kubectl -n prod create token jenkins --duration=24h)
CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
cat > /tmp/jenkins-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- name: lab
  cluster: {server: https://127.0.0.1:6443, certificate-authority-data: $CA}
users:
- name: jenkins
  user: {token: $TOKEN}
contexts:
- name: jenkins
  context: {cluster: lab, user: jenkins, namespace: prod}
current-context: jenkins
EOF

C=$(mktemp); CRUMB=$(curl -sf -c $C -u admin:admin "$J/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")
B64=$(base64 -w0 /tmp/jenkins-kubeconfig)
cat > /tmp/cred.groovy <<EOF
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.Domain
import org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl
def bytes = "$B64".decodeBase64()
def c = new FileCredentialsImpl(CredentialsScope.GLOBAL, 'kubeconfig', 'lab cluster, prod SA', 'kubeconfig', SecretBytes.fromBytes(bytes))
SystemCredentialsProvider.getInstance().getStore().addCredentials(Domain.global(), c)
println 'ok'
EOF
curl -sf -b $C -u admin:admin -H "$CRUMB" --data-urlencode "script@/tmp/cred.groovy" $J/scriptText

# 3) Pipeline files in the repo.
cd /root/java-maven-app
sed -i 's#java-maven-app-1.0-SNAPSHOT.jar#app.jar#; s#COPY ./target/java-maven-app-\*.jar /usr/app/#COPY ./target/java-maven-app-*.jar /usr/app/app.jar#' Dockerfile
mkdir -p kubernetes
cat > kubernetes/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: java-maven-app, labels: {app: java-maven-app}}
spec:
  replicas: 1
  selector: {matchLabels: {app: java-maven-app}}
  template:
    metadata: {labels: {app: java-maven-app}}
    spec:
      containers:
      - name: app
        image: $IMAGE
        ports: [{containerPort: 8080}]
        readinessProbe: {httpGet: {path: /, port: 8080}, initialDelaySeconds: 10}
---
apiVersion: v1
kind: Service
metadata: {name: java-maven-app}
spec:
  selector: {app: java-maven-app}
  ports: [{port: 8080, targetPort: 8080}]
EOF
cat > Jenkinsfile <<'EOF'
pipeline {
    agent any
    tools { maven 'Maven' }
    environment {
        IMAGE = "localhost:5000/java-maven-app:1.1.0-${BUILD_NUMBER}"
    }
    stages {
        stage('build jar') {
            steps { sh 'mvn -B package' }
        }
        stage('build image') {
            steps {
                sh 'docker build -t $IMAGE .'
                sh 'docker push $IMAGE'
            }
        }
        stage('deploy') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh 'sed "s#\\$IMAGE#$IMAGE#" kubernetes/deployment.yaml | kubectl apply -f -'
                    sh 'kubectl rollout status deployment/java-maven-app --timeout=180s'
                }
            }
        }
    }
}
EOF
git add -A && git commit -qm "pipeline"

# 4) Build and wait.
curl -sf -b $C -u admin:admin -H "$CRUMB" -X POST $J/job/java-maven-app/build
sleep 15
for i in $(seq 1 120); do
  s=$(curl -s -u admin:admin $J/job/java-maven-app/lastBuild/api/json || true)
  echo "$s" | grep -q '"building":false' && break; sleep 5
done
curl -s -u admin:admin $J/job/java-maven-app/lastBuild/consoleText | tail -40
