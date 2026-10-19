#!/bin/bash
# Seeds: k3s (EKS stand-in), registry on :5000 (ECR stand-in), Jenkins in Docker
# with Maven + docker CLI (no kubectl, the candidate wires up cluster access),
# a starter app repo, and a pipeline job pointing at it. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE -o pipefail
rm -f /tmp/setup-done /tmp/setup-failed

APP_REPO=https://gitlab.com/twn-devops-bootcamp/latest/11-eks/java-maven-app.git
APP_SHA=04a40816abffed5ed9612f8fc091e26d99f48ac0
DOCKER_VERSION=29.8.0
K3S_VERSION=v1.36.5+k3s1
JENKINS_IMAGE=jenkins/jenkins:2.568.3-lts-jdk21
DOCKERCLI_IMAGE=docker:29.8.0-cli
MAVEN_IMAGE=maven:3.9.15-eclipse-temurin-21
REGISTRY_IMAGE=registry:2.8.3
APP_BASE_IMAGE=amazoncorretto:17-alpine-jdk   # FROM line of the course Dockerfile
JH=/var/lib/jenkins-lab

# --- Docker, with a Docker Hub pull-through mirror (shared egress IPs hit rate limits) ---
if ! command -v docker >/dev/null; then
  curl -fsSL --retry 3 https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh --version "$DOCKER_VERSION"
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

# --- Clear our own previous containers, then make sure the ports are ours ---
docker rm -f registry jenkins 2>/dev/null || true
busy=""
for p in 5000 8080 50000; do ss -ltnH "sport = :$p" | grep -q . && busy="$busy $p"; done
if ! systemctl is-active -q k3s 2>/dev/null; then
  for p in 6443 10250; do ss -ltnH "sport = :$p" | grep -q . && busy="$busy $p"; done
fi
if [ -n "$busy" ]; then echo "ERROR: ports already in use:$busy"; ss -ltnp; false; fi

# --- Pull images in the background (retries; any failure fails setup) ---
pull() {
  for i in 1 2 3 4 5; do docker pull -q "$1" && return 0; sleep $((i * 10)); done
  echo "ERROR: could not pull $1"; return 1
}
pids=()
for img in $REGISTRY_IMAGE $JENKINS_IMAGE $DOCKERCLI_IMAGE $MAVEN_IMAGE $APP_BASE_IMAGE; do
  pull "$img" & pids+=($!)
done

# --- k3s (EKS stand-in); nodes pull from the plain-http local registry ---
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
  docker.io:
    endpoint:
      - "https://mirror.gcr.io"
EOF
curl -sfL --retry 3 https://get.k3s.io -o /tmp/k3s-install.sh
INSTALL_K3S_VERSION="$K3S_VERSION" INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh /tmp/k3s-install.sh
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p /root/.kube && cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
grep -q KUBECONFIG /root/.bashrc || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc
for i in $(seq 1 60); do kubectl get nodes 2>/dev/null | grep -q ' Ready' && break; sleep 3; done

for p in "${pids[@]}"; do wait "$p"; done

# --- Registry (ECR stand-in) ---
docker run -d --restart=always --name registry -p 5000:5000 $REGISTRY_IMAGE

# --- Starter app repo (course code, without the pipeline files) ---
rm -rf /root/java-maven-app
for i in 1 2 3; do git clone -q "$APP_REPO" /root/java-maven-app && break; rm -rf /root/java-maven-app; sleep 10; done
cd /root/java-maven-app
git checkout -q "$APP_SHA"
rm -rf .git Jenkinsfile script.groovy
git init -q -b master
git config user.email "you@example.com"; git config user.name "You"
git add -A && git commit -qm "starting code"
git config --global --get-all safe.directory | grep -qx /root/java-maven-app \
  || git config --global --add safe.directory /root/java-maven-app
cd /

# --- Jenkins image: pinned LTS + pinned plugins + Maven + docker CLI ---
mkdir -p /opt/jenkins-lab
cat > /opt/jenkins-lab/plugins.txt <<'EOF'
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
cat > /opt/jenkins-lab/Dockerfile <<EOF
FROM $DOCKERCLI_IMAGE AS dockercli
FROM $MAVEN_IMAGE AS mvn
FROM $JENKINS_IMAGE
USER root
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=mvn /usr/share/maven /usr/share/maven
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN ln -s /usr/share/maven/bin/mvn /usr/local/bin/mvn \\
 && for i in 1 2 3; do jenkins-plugin-cli --latest false --plugin-file /usr/share/jenkins/ref/plugins.txt && exit 0; sleep 15; done; exit 1
ENV JAVA_OPTS="-Xmx1g -Djenkins.install.runSetupWizard=false -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF
docker build -q -t jenkins-lab /opt/jenkins-lab

mkdir -p $JH/jobs/java-maven-app
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
        <hudson.plugins.git.UserRemoteConfig><url>file:///host-root/java-maven-app</url></hudson.plugins.git.UserRemoteConfig>
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
# the same way the host does. Runs as root so the docker socket just works; HOME
# is JENKINS_HOME as for the stock jenkins user. /root is mounted read-only (not
# the repo dir itself) so a re-cloned /root/java-maven-app is still what Jenkins sees.
docker run -d --restart=always --name jenkins --network host -u root \
  -e HOME=/var/jenkins_home \
  -v $JH:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /root:/host-root:ro \
  jenkins-lab
for i in $(seq 1 90); do
  curl -sf -u admin:admin http://localhost:8080/job/java-maven-app/api/json >/dev/null 2>&1 && break; sleep 3
done
curl -sf -u admin:admin http://localhost:8080/job/java-maven-app/api/json >/dev/null
docker exec jenkins sh -c 'git config --global --get-all safe.directory | grep -qx /host-root/java-maven-app || git config --global --add safe.directory /host-root/java-maven-app'

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/bin/bash
# Pass when the latest Jenkins build is green, pushed a unique tag to the local
# registry, and prod runs that exact image (by digest) behind a working Service.
fail() { echo "❌ NOT YET: $1"; exit 0; }
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
J="curl -sf --max-time 10 -u admin:admin http://localhost:8080"
REG=http://localhost:5000
REPO=localhost:5000/java-maven-app
js() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

$J/api/json >/dev/null 2>&1 || fail "Jenkins is not answering on :8080 (docker ps / docker logs jenkins)."
$J/job/java-maven-app/api/json >/dev/null 2>&1 || fail "The Jenkins job java-maven-app is missing."
last=$($J/job/java-maven-app/lastBuild/api/json 2>/dev/null) || fail "The java-maven-app job has never run."
num=$(echo "$last" | js 'd["number"]')
[ "$(echo "$last" | js 'd["building"]')" = False ] || fail "Build #$num is still running; wait for it to finish."
[ "$(echo "$last" | js 'd["result"]')" = SUCCESS ] || fail "The latest java-maven-app build (#$num) is not green."
log=$($J/job/java-maven-app/$num/consoleText 2>/dev/null | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')

curl -sf --max-time 5 $REG/v2/ >/dev/null 2>&1 || fail "The registry at localhost:5000 is not answering (docker ps -a | grep registry)."
tags=$(curl -sf --max-time 5 $REG/v2/java-maven-app/tags/list 2>/dev/null)
echo "$tags" | grep -q '"tags":\[' || fail "No java-maven-app image in the registry at localhost:5000."

img=$(kubectl -n prod get deploy java-maven-app -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
[ -n "$img" ] || fail "No Deployment java-maven-app in namespace prod."
case "$img" in "$REPO":*) ;; *) fail "Deployment image is '$img', expected one from $REPO.";; esac
tag=${img##*:}
[ "$tag" != latest ] || fail "Deployment uses the 'latest' tag; each build needs its own tag."
echo "$tags" | grep -qF "\"$tag\"" || fail "Tag $tag is not in the registry (tags: $tags)."
digest=$(curl -sfI --max-time 5 \
  -H 'Accept: application/vnd.oci.image.index.v1+json' \
  -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  $REG/v2/java-maven-app/manifests/$tag | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
[ -n "$digest" ] || fail "Could not read the manifest of $REPO:$tag from the registry."
{ grep -qF "$digest" <<<"$log" || grep -qF "$tag: digest:" <<<"$log" || grep -qF "$REPO:$tag" <<<"$log"; } \
  || fail "Build #$num did not push $REPO:$tag; prod is not running what the latest build produced."

if ! kubectl -n prod rollout status deploy/java-maven-app --timeout=5s >/dev/null 2>&1; then
  why=$(kubectl -n prod get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[*].state.waiting.reason}{" "}{.status.containerStatuses[*].state.terminated.reason}{" "}{end}' 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')
  fail "Deployment java-maven-app in prod is not fully rolled out${why:+ (pods: $why)}. Look at kubectl -n prod get pods and kubectl -n prod logs <pod>."
fi
ready=$(kubectl -n prod get deploy java-maven-app -o jsonpath='{.status.readyReplicas}')
[ "${ready:-0}" -ge 1 ] || fail "No ready pods for java-maven-app in prod."
sel=$(kubectl -n prod get deploy java-maven-app -o json | js '",".join(k+"="+v for k,v in d["spec"]["selector"].get("matchLabels",{}).items())')
ids=$(kubectl -n prod get pods -l "$sel" -o json 2>/dev/null | js '"\n".join(c.get("imageID","") for p in d["items"] if not p["metadata"].get("deletionTimestamp") for c in p["status"].get("containerStatuses",[]) if c.get("ready"))')
grep -qF "@$digest" <<<"$ids" \
  || fail "The ready pods in prod are not running the image the registry holds as $REPO:$tag ($digest)."

ip=$(kubectl -n prod get svc java-maven-app -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
[ -n "$ip" ] || fail "No Service java-maven-app in namespace prod."
kubectl -n prod get svc java-maven-app -o jsonpath='{.spec.ports[*].port}' | grep -qw 8080 \
  || fail "Service java-maven-app does not expose port 8080."
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$ip:8080/)
[ "$code" != 000 ] || fail "Service java-maven-app:8080 is not answering (no endpoints? kubectl -n prod get endpoints java-maven-app)."
[ "$code" = 200 ] || fail "Service java-maven-app:8080 answers HTTP $code, not the app's page."

echo "✅ PASS: build #$num pushed $REPO:$tag and prod is serving it on java-maven-app:8080."
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

# --- self-test: what the candidate relies on ---
kubectl version
kubectl get nodes | grep -q ' Ready'
kubectl -n kube-system rollout status deploy/coredns --timeout=180s
curl -sf http://localhost:5000/v2/ >/dev/null
docker exec jenkins mvn -v
docker exec jenkins docker version
docker exec jenkins git ls-remote file:///host-root/java-maven-app master | grep -q refs/heads/master
curl -sf -u admin:admin http://localhost:8080/crumbIssuer/api/json >/dev/null
curl -sf -u admin:admin 'http://localhost:8080/pluginManager/api/json?depth=1&tree=plugins[shortName,version]' \
  | python3 -c 'import sys,json; print("\n".join(sorted(p["shortName"]+":"+p["version"] for p in json.load(sys.stdin)["plugins"])))' | sort > /tmp/plugins-running.txt
diff <(sort /opt/jenkins-lab/plugins.txt) /tmp/plugins-running.txt
out=$(/usr/local/bin/check); echo "$out"; grep -q 'NOT YET' <<<"$out"

touch /tmp/setup-done
