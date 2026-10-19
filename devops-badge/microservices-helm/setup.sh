#!/bin/bash
# Seeds: k3s (servicelb on, traefik off), helm + helm-diff + helmfile, the Online
# Boutique images pre-pulled, and plain starter manifests in /root/online-boutique.
# The candidate turns them into a Helm/helmfile deployment with production
# practices. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE
set -o pipefail

K3S_VERSION=v1.36.5+k3s1
HELM_VERSION=v3.22.0
HELMFILE_VERSION=1.8.0
HELM_DIFF_VERSION=v3.15.14
APP_VERSION=v0.10.4
REDIS_PINNED=redis:7.4-alpine
IMG=us-central1-docker.pkg.dev/google-samples/microservices-demo
SERVICES="currencyservice productcatalogservice checkoutservice shippingservice cartservice emailservice paymentservice frontend recommendationservice adservice"

retry() { local i; for i in 1 2 3 4 5; do "$@" && return 0; sleep $((i * 5)); done; echo "FAILED after 5 tries: $*"; return 1; }

# --- ports: servicelb publishes the shop's LoadBalancer on host port 80 ---
if ! systemctl is-active -q k3s; then
  for p in 80 6443; do
    if ss -ltnH "( sport = :$p )" | grep -q .; then
      echo "Port $p is already in use, the lab needs it:"; ss -ltnp "( sport = :$p )"; exit 1
    fi
  done
fi

# --- k3s (Docker Hub through mirror.gcr.io: Killercoda VMs share egress IPs) ---
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.gcr.io"
EOF
curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
INSTALL_K3S_VERSION=$K3S_VERSION INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh /tmp/k3s-install.sh
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for i in $(seq 1 60); do kubectl get nodes 2>/dev/null | grep -q ' Ready' && break; sleep 3; done
mkdir -p /root/.kube && cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
grep -q KUBECONFIG /root/.bashrc || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc

# --- helm, helm-diff, helmfile (pinned release tarballs) ---
curl -fsSL https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz -o /tmp/helm.tgz
tar -xzf /tmp/helm.tgz -C /usr/local/bin --strip-components=1 linux-amd64/helm
export HOME=/root
helm plugin list | grep -q '^diff' || retry helm plugin install https://github.com/databus23/helm-diff --version $HELM_DIFF_VERSION
curl -fsSL https://github.com/helmfile/helmfile/releases/download/v$HELMFILE_VERSION/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz -o /tmp/helmfile.tgz
tar -xzf /tmp/helmfile.tgz -C /usr/local/bin helmfile

# --- pre-pull images so pods start fast (crictl honours the docker.io mirror) ---
pids=()
for ref in $(for s in $SERVICES; do echo "$IMG/$s:$APP_VERSION"; done) docker.io/library/redis:alpine docker.io/library/$REDIS_PINNED; do
  retry k3s crictl pull "$ref" >/dev/null & pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done

# --- starter: plain manifests that work with kubectl apply, nothing more ---
rm -rf /root/online-boutique
mkdir -p /root/online-boutique
cat > /root/online-boutique/config.yaml <<'MANIFEST_EOF'
# Online Boutique, plain manifests (works with kubectl apply, but not production-ready)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: currencyservice
  labels:
    app: currencyservice
spec:
  selector:
    matchLabels:
      app: currencyservice
  template:
    metadata:
      labels:
        app: currencyservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/currencyservice:v0.10.4
        ports:
        - name: grpc
          containerPort: 7000
        env:
        - name: PORT
          value: '7000'
        - name: DISABLE_PROFILER
          value: '1'
---
apiVersion: v1
kind: Service
metadata:
  name: currencyservice
  labels:
    app: currencyservice
spec:
  type: ClusterIP
  selector:
    app: currencyservice
  ports:
  - name: grpc
    port: 7000
    targetPort: 7000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: productcatalogservice
  labels:
    app: productcatalogservice
spec:
  selector:
    matchLabels:
      app: productcatalogservice
  template:
    metadata:
      labels:
        app: productcatalogservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/productcatalogservice:v0.10.4
        ports:
        - containerPort: 3550
        env:
        - name: PORT
          value: '3550'
        - name: DISABLE_PROFILER
          value: '1'
---
apiVersion: v1
kind: Service
metadata:
  name: productcatalogservice
  labels:
    app: productcatalogservice
spec:
  type: ClusterIP
  selector:
    app: productcatalogservice
  ports:
  - name: grpc
    port: 3550
    targetPort: 3550
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkoutservice
  labels:
    app: checkoutservice
spec:
  selector:
    matchLabels:
      app: checkoutservice
  template:
    metadata:
      labels:
        app: checkoutservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/checkoutservice:v0.10.4
        ports:
        - containerPort: 5050
        env:
        - name: PORT
          value: '5050'
        - name: PRODUCT_CATALOG_SERVICE_ADDR
          value: productcatalogservice:3550
        - name: SHIPPING_SERVICE_ADDR
          value: shippingservice:50051
        - name: PAYMENT_SERVICE_ADDR
          value: paymentservice:50051
        - name: EMAIL_SERVICE_ADDR
          value: emailservice:5000
        - name: CURRENCY_SERVICE_ADDR
          value: currencyservice:7000
        - name: CART_SERVICE_ADDR
          value: cartservice:7070
---
apiVersion: v1
kind: Service
metadata:
  name: checkoutservice
  labels:
    app: checkoutservice
spec:
  type: ClusterIP
  selector:
    app: checkoutservice
  ports:
  - name: grpc
    port: 5050
    targetPort: 5050
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shippingservice
  labels:
    app: shippingservice
spec:
  selector:
    matchLabels:
      app: shippingservice
  template:
    metadata:
      labels:
        app: shippingservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/shippingservice:v0.10.4
        ports:
        - containerPort: 50051
        env:
        - name: PORT
          value: '50051'
        - name: DISABLE_PROFILER
          value: '1'
---
apiVersion: v1
kind: Service
metadata:
  name: shippingservice
  labels:
    app: shippingservice
spec:
  type: ClusterIP
  selector:
    app: shippingservice
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cartservice
  labels:
    app: cartservice
spec:
  selector:
    matchLabels:
      app: cartservice
  template:
    metadata:
      labels:
        app: cartservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/cartservice:v0.10.4
        ports:
        - containerPort: 7070
        env:
        - name: REDIS_ADDR
          value: redis-cart:6379
---
apiVersion: v1
kind: Service
metadata:
  name: cartservice
  labels:
    app: cartservice
spec:
  type: ClusterIP
  selector:
    app: cartservice
  ports:
  - name: grpc
    port: 7070
    targetPort: 7070
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cart
  labels:
    app: redis-cart
spec:
  selector:
    matchLabels:
      app: redis-cart
  template:
    metadata:
      labels:
        app: redis-cart
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - mountPath: /data
          name: redis-data
      volumes:
      - name: redis-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cart
  labels:
    app: redis-cart
spec:
  type: ClusterIP
  selector:
    app: redis-cart
  ports:
  - name: tcp-redis
    port: 6379
    targetPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: emailservice
  labels:
    app: emailservice
spec:
  selector:
    matchLabels:
      app: emailservice
  template:
    metadata:
      labels:
        app: emailservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/emailservice:v0.10.4
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: '8080'
        - name: DISABLE_PROFILER
          value: '1'
---
apiVersion: v1
kind: Service
metadata:
  name: emailservice
  labels:
    app: emailservice
spec:
  type: ClusterIP
  selector:
    app: emailservice
  ports:
  - name: grpc
    port: 5000
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: paymentservice
  labels:
    app: paymentservice
spec:
  selector:
    matchLabels:
      app: paymentservice
  template:
    metadata:
      labels:
        app: paymentservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/paymentservice:v0.10.4
        ports:
        - containerPort: 50051
        env:
        - name: PORT
          value: '50051'
        - name: DISABLE_PROFILER
          value: '1'
---
apiVersion: v1
kind: Service
metadata:
  name: paymentservice
  labels:
    app: paymentservice
spec:
  type: ClusterIP
  selector:
    app: paymentservice
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
      annotations:
        sidecar.istio.io/rewriteAppHTTPProbers: 'true'
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/frontend:v0.10.4
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: '8080'
        - name: PRODUCT_CATALOG_SERVICE_ADDR
          value: productcatalogservice:3550
        - name: CURRENCY_SERVICE_ADDR
          value: currencyservice:7000
        - name: CART_SERVICE_ADDR
          value: cartservice:7070
        - name: RECOMMENDATION_SERVICE_ADDR
          value: recommendationservice:8080
        - name: SHIPPING_SERVICE_ADDR
          value: shippingservice:50051
        - name: CHECKOUT_SERVICE_ADDR
          value: checkoutservice:5050
        - name: AD_SERVICE_ADDR
          value: adservice:9555
        - name: SHOPPING_ASSISTANT_SERVICE_ADDR
          value: shoppingassistantservice:80
        - name: ENABLE_PROFILER
          value: '0'
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-external
  labels:
    app: frontend
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: recommendationservice
  labels:
    app: recommendationservice
spec:
  selector:
    matchLabels:
      app: recommendationservice
  template:
    metadata:
      labels:
        app: recommendationservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/recommendationservice:v0.10.4
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: '8080'
        - name: PRODUCT_CATALOG_SERVICE_ADDR
          value: productcatalogservice:3550
        - name: DISABLE_PROFILER
          value: '1'
---
apiVersion: v1
kind: Service
metadata:
  name: recommendationservice
  labels:
    app: recommendationservice
spec:
  type: ClusterIP
  selector:
    app: recommendationservice
  ports:
  - name: grpc
    port: 8080
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: adservice
  labels:
    app: adservice
spec:
  selector:
    matchLabels:
      app: adservice
  template:
    metadata:
      labels:
        app: adservice
    spec:
      containers:
      - name: server
        image: us-central1-docker.pkg.dev/google-samples/microservices-demo/adservice:v0.10.4
        ports:
        - containerPort: 9555
        env:
        - name: PORT
          value: '9555'
---
apiVersion: v1
kind: Service
metadata:
  name: adservice
  labels:
    app: adservice
spec:
  type: ClusterIP
  selector:
    app: adservice
  ports:
  - name: grpc
    port: 9555
    targetPort: 9555
MANIFEST_EOF
cd /root/online-boutique
git init -q -b main
git config user.email "you@example.com"; git config user.name "You"
git add -A && git commit -qm "plain manifests"
cd /

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/usr/bin/env python3
# Pass when all 11 services run in `microservices` from Helm releases (one shared
# chart for the app services, all listed in helmfile.yaml[.gotmpl]), every container
# follows the production basics, the shop answers on host port 80 and a real
# checkout goes through the storefront.
import json, os, re, subprocess, sys, http.cookiejar, urllib.parse, urllib.request

os.environ["KUBECONFIG"] = "/etc/rancher/k3s/k3s.yaml"
NS = "microservices"
DIR = "/root/online-boutique"
APPS = ["currencyservice", "productcatalogservice", "checkoutservice", "shippingservice",
        "cartservice", "emailservice", "paymentservice", "frontend",
        "recommendationservice", "adservice"]
ALL = APPS + ["redis-cart"]

def fail(msg):
    print(f"❌ NOT YET: {msg}"); sys.exit(0)

def run(*cmd, cwd=None):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return r.returncode, r.stdout

rc, out = run("kubectl", "get", "ns", NS)
rc == 0 or fail(f"Namespace {NS} does not exist.")
rc, out = run("kubectl", "-n", NS, "get", "deploy", "-o", "json")
deps = {d["metadata"]["name"]: d for d in json.loads(out or '{"items":[]}')["items"]}
missing = [n for n in ALL if n not in deps]
missing and fail(f"Missing Deployments in {NS}: {', '.join(missing)}.")

# Helm: every Deployment from a release, the app services from one shared chart
rc, out = run("helm", "list", "-n", NS, "-o", "json")
charts = {r["name"]: re.sub(r"-v?\d+\.\d+\.\d+.*$", "", r["chart"]) for r in json.loads(out or "[]")}
release_of = {}
for n in ALL:
    rel = (deps[n]["metadata"].get("annotations") or {}).get("meta.helm.sh/release-name")
    rel in charts or fail(f"Deployment {n} is not managed by a Helm release (helm list -n {NS}).")
    release_of[n] = rel
app_charts = {charts[release_of[n]] for n in APPS}
len(app_charts) == 1 or fail(f"The 10 application services should share ONE reusable chart; they use: {', '.join(sorted(app_charts))}.")

# helmfile: one file that declares every release (helmfile v1 reads helmfile.yaml or helmfile.yaml.gotmpl)
HF = [f for f in ("helmfile.yaml", "helmfile.yaml.gotmpl") if os.path.isfile(f"{DIR}/{f}")]
HF or fail(f"No {DIR}/helmfile.yaml (or helmfile.yaml.gotmpl).")
rc, out = run("helmfile", "-f", HF[0], "list", "--output", "json", cwd=DIR)
rc == 0 or fail(f"helmfile list fails on your {HF[0]} (run it in /root/online-boutique to see why).")
try:
    declared = {r.get("name") for r in json.loads(out or "[]")}
except ValueError:
    fail(f"helmfile list on {HF[0]} printed no release list.")
undeclared = sorted({release_of[n] for n in ALL} - declared)
undeclared and fail(f"Releases not declared in {HF[0]}: {', '.join(undeclared)}.")

# production basics, per container
for n in ALL:
    spec = deps[n]["spec"]
    want = 1 if n == "redis-cart" else 2
    if (spec.get("replicas") or 1) < want:
        fail(f"{n} runs {spec.get('replicas') or 1} replica(s); stateless services need at least 2.")
    for c in spec["template"]["spec"]["containers"]:
        img = c["image"]
        tag = img.split("@")[0].rsplit("/", 1)[-1].partition(":")[2]
        if "@sha256:" not in img and (not tag or not re.search(r"\d", tag)):
            fail(f"{n}: image '{img}' is not pinned to a version.")
        for p in ("livenessProbe", "readinessProbe"):
            c.get(p) or fail(f"{n}: container {c['name']} has no {p}.")
        res = c.get("resources") or {}
        for kind in ("requests", "limits"):
            for r in ("cpu", "memory"):
                (res.get(kind) or {}).get(r) or fail(f"{n}: container {c['name']} has no {kind}.{r}.")

# everything up
for n in ALL:
    st = deps[n].get("status", {})
    if (st.get("availableReplicas") or 0) < (deps[n]["spec"].get("replicas") or 1):
        fail(f"{n} is not fully available ({st.get('availableReplicas') or 0}/{deps[n]['spec'].get('replicas') or 1}); kubectl -n {NS} get pods.")

# the shop works end to end: storefront, product page, cart, checkout
rc, ip = run("kubectl", "-n", NS, "get", "svc", "frontend", "-o", "jsonpath={.spec.clusterIP}")
ip or fail("No Service frontend in microservices.")
rc, port = run("kubectl", "-n", NS, "get", "svc", "frontend", "-o", "jsonpath={.spec.ports[0].port}")
base = f"http://{ip}:{port or 80}"
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def get(path, data=None):
    try:
        r = op.open(base + path, urllib.parse.urlencode(data).encode() if data else None, timeout=20)
        return r.status, r.read().decode(errors="replace")
    except Exception as e:
        return getattr(e, "code", None), ""
code, body = get("/")
code == 200 or fail(f"Storefront {base}/ answers HTTP {code}.")
code, body = get("/product/OLJCESPC7Z")
code == 200 or fail(f"Product page answers HTTP {code} (productcatalog / currency / recommendation / ad).")
code, body = get("/cart", {"product_id": "OLJCESPC7Z", "quantity": "1"})
code == 200 or fail(f"Adding to cart answers HTTP {code} (cartservice / redis-cart).")
code, body = get("/cart/checkout", {
    "email": "someone@example.com", "street_address": "1600 Amphitheatre Parkway",
    "zip_code": "94043", "city": "Mountain View", "state": "CA", "country": "United States",
    "credit_card_number": "4432801561520454", "credit_card_expiration_month": "1",
    "credit_card_expiration_year": "2030", "credit_card_cvv": "672"})
(code == 200 and "order is complete" in body.lower()) or fail(
    f"Checkout does not complete (HTTP {code}); checkout / payment / shipping / email / cart are involved.")

# customers reach the shop from outside: a LoadBalancer Service on port 80 of this machine
try:
    r = urllib.request.urlopen("http://127.0.0.1:80/", timeout=20)
    ext_code, ext_body = r.status, r.read().decode(errors="replace")
except Exception as e:
    ext_code, ext_body = getattr(e, "code", None), ""
(ext_code == 200 and "Online Boutique" in ext_body) or fail(
    f"The shop does not answer on port 80 of this machine (HTTP {ext_code}); customers need a LoadBalancer Service on port 80 "
    f"(kubectl -n {NS} get svc).")

print(f"✅ PASS: all 11 services run from Helm releases in {NS}, declared in {HF[0]}, the shop answers on port 80 and a checkout completes.")
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

# --- self-test: what the candidate relies on ---
helm version --short | grep -q "$HELM_VERSION"
helm plugin list | grep -q '^diff'
helmfile version | grep -q "$HELMFILE_VERSION"
kubectl version
kubectl get nodes | grep -q ' Ready'
for s in $SERVICES; do k3s crictl inspecti "$IMG/$s:$APP_VERSION" >/dev/null; done
k3s crictl inspecti docker.io/library/$REDIS_PINNED >/dev/null
/usr/local/bin/check | grep -q 'NOT YET'

touch /tmp/setup-done
