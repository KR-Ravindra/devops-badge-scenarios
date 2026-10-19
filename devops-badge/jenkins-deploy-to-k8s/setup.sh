#!/bin/bash
# Seeds: k3s (EKS stand-in), registry:2 on :5000 (ECR stand-in), Jenkins in Docker
# with Maven + docker CLI (no kubectl, the candidate wires up cluster access),
# a starter app repo, and a pipeline job pointing at it. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE

APP_REPO=https://gitlab.com/twn-devops-bootcamp/latest/11-eks/java-maven-app.git
APP_SHA=04a40816abffed5ed9612f8fc091e26d99f48ac0
JH=/var/lib/jenkins-lab

# --- Docker ---
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done

# --- Registry (ECR stand-in) ---
docker rm -f registry 2>/dev/null || true
docker run -d --restart=always --name registry -p 5000:5000 registry:2

# --- k3s (EKS stand-in); nodes pull from the plain-http local registry ---
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
EOF
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for i in $(seq 1 60); do kubectl get nodes 2>/dev/null | grep -q ' Ready' && break; sleep 3; done
grep -q KUBECONFIG /root/.bashrc || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc

# --- Starter app repo (course code, without the pipeline files) ---
rm -rf /root/java-maven-app
git clone -q "$APP_REPO" /root/java-maven-app
cd /root/java-maven-app
git checkout -q "$APP_SHA"
rm -rf .git Jenkinsfile script.groovy
git init -q -b master
git config user.email "you@example.com"; git config user.name "You"
git add -A && git commit -qm "starting code"
git config --global --add safe.directory /root/java-maven-app
cd /

# --- Jenkins image: LTS + pipeline plugins + Maven + docker CLI ---
mkdir -p /opt/jenkins-lab
cat > /opt/jenkins-lab/Dockerfile <<'EOF'
FROM docker:27-cli AS dockercli
FROM maven:3.9-eclipse-temurin-17 AS mvn
FROM jenkins/jenkins:lts-jdk17
USER root
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=mvn /usr/share/maven /usr/share/maven
RUN ln -s /usr/share/maven/bin/mvn /usr/local/bin/mvn \
 && jenkins-plugin-cli --plugins workflow-aggregator git credentials-binding plain-credentials configuration-as-code
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF
docker build -q -t jenkins-lab /opt/jenkins-lab

mkdir -p $JH/jobs/java-maven-app
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
tool:
  maven:
    installations:
      - name: Maven
        home: /usr/share/maven
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

# Host network: Jenkins reaches the registry and the API server (127.0.0.1:6443)
# the same way the host does. Runs as root so the docker socket just works.
docker rm -f jenkins 2>/dev/null || true
docker run -d --restart=always --name jenkins --network host -u root \
  -v $JH:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /root/java-maven-app:/repos/java-maven-app:ro \
  jenkins-lab
for i in $(seq 1 90); do
  curl -sf -u admin:admin http://localhost:8080/job/java-maven-app/api/json >/dev/null 2>&1 && break; sleep 3
done
curl -sf -u admin:admin http://localhost:8080/job/java-maven-app/api/json >/dev/null
docker exec jenkins git config --global --add safe.directory /repos/java-maven-app

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/bin/bash
# Pass when the latest Jenkins build is green, pushed a unique tag to the local
# registry, and prod runs that exact image behind a working Service.
fail() { echo "❌ NOT YET: $1"; exit 0; }
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
J="curl -s --max-time 10 -u admin:admin http://localhost:8080"
REPO=localhost:5000/java-maven-app

$J/api/json >/dev/null 2>&1 || fail "Jenkins is not answering on :8080 (docker ps / docker logs jenkins)."
last=$($J/job/java-maven-app/lastBuild/api/json 2>/dev/null)
[ -n "$last" ] || fail "The java-maven-app job has never run."
echo "$last" | grep -q '"building":true' && fail "A build is still running; wait for it to finish."
echo "$last" | grep -q '"result":"SUCCESS"' || fail "The latest java-maven-app build is not green."
num=$(echo "$last" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
log=$($J/job/java-maven-app/$num/consoleText 2>/dev/null)

tags=$(curl -s --max-time 5 http://localhost:5000/v2/java-maven-app/tags/list 2>/dev/null)
echo "$tags" | grep -q '"tags":\[' || fail "No java-maven-app image in the registry at localhost:5000."

img=$(kubectl -n prod get deploy java-maven-app -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
[ -n "$img" ] || fail "No Deployment java-maven-app in namespace prod."
case "$img" in "$REPO":*) ;; *) fail "Deployment image is '$img', expected one from $REPO.";; esac
tag=${img##*:}
[ "$tag" != latest ] || fail "Deployment uses the 'latest' tag; each build needs its own tag."
echo "$tags" | grep -q "\"$tag\"" || fail "Tag $tag is not in the registry (tags: $tags)."
echo "$log" | grep -q "$REPO:$tag" || fail "Build #$num did not push/deploy $REPO:$tag; prod is not running what the latest build produced."

kubectl -n prod rollout status deploy/java-maven-app --timeout=5s >/dev/null 2>&1 \
  || fail "Deployment java-maven-app is not fully rolled out (kubectl -n prod get pods)."
ready=$(kubectl -n prod get deploy java-maven-app -o jsonpath='{.status.readyReplicas}')
[ "${ready:-0}" -ge 1 ] || fail "No ready pods for java-maven-app in prod."

ip=$(kubectl -n prod get svc java-maven-app -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
[ -n "$ip" ] || fail "No Service java-maven-app in namespace prod."
kubectl -n prod get svc java-maven-app -o jsonpath='{.spec.ports[*].port}' | grep -qw 8080 \
  || fail "Service java-maven-app does not expose port 8080."
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$ip:8080/)
[ "$code" = 200 ] || fail "Service java-maven-app:8080 does not answer with the app (HTTP ${code:-none})."

echo "✅ PASS: build #$num pushed $REPO:$tag and prod is serving it on java-maven-app:8080."
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

touch /tmp/setup-done
