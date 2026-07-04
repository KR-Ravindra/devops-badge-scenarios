#!/bin/bash
# Background setup: seed 3 healthy-but-unexposed deployments. No Services, no Ingress.
set -e

kubectl create namespace apps >/dev/null 2>&1 || true

# Two HTTP web apps (echo server on 8080).
for app in web-a web-b; do
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app}
  namespace: apps
  labels: { app: ${app} }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${app} } }
  template:
    metadata: { labels: { app: ${app} } }
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo:1.0
        args: ["-text=hello from ${app}", "-listen=:8080"]
        ports: [ { containerPort: 8080 } ]
EOF
done

# FTP app (TCP:21). vsftpd-style container; any TCP listener on 21 is fine for grading.
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ftp-app
  namespace: apps
  labels: { app: ftp-app }
spec:
  replicas: 1
  selector: { matchLabels: { app: ftp-app } }
  template:
    metadata: { labels: { app: ftp-app } }
    spec:
      containers:
      - name: ftp
        image: alpine:3.20
        command: ["/bin/sh","-c","apk add --no-cache socat >/dev/null 2>&1; socat TCP-LISTEN:21,reuseaddr,fork SYSTEM:'echo 220 fake-ftp ready'"]
        ports: [ { containerPort: 21 } ]
EOF

kubectl -n apps rollout status deploy/web-a --timeout=120s >/dev/null 2>&1 || true
kubectl -n apps rollout status deploy/web-b --timeout=120s >/dev/null 2>&1 || true
kubectl -n apps rollout status deploy/ftp-app --timeout=120s >/dev/null 2>&1 || true

# Signal readiness for KillerCoda step verification pattern.
touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Verify web-a and web-b are reachable through the ingress controller by host header.
# Grades behaviour (does it route?), not the exact YAML the candidate wrote.

fail() { echo "❌ $1"; exit 0; }

# Resolve the ingress controller's in-cluster entry point. On kubeadm-1node the
# controller is typically reachable on the node via a NodePort or hostPort :80.
INGRESS_PORT=$(kubectl -n ingress-nginx get svc -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
INGRESS_PORT=${INGRESS_PORT:-80}

check_host() {
  local host="$1" expect="$2"
  # Try NodePort first, then plain :80 (hostPort/hostNetwork controllers).
  for url in "http://localhost:${INGRESS_PORT}/" "http://localhost/"; do
    body=$(curl -s --max-time 5 -H "Host: ${host}" "$url" 2>/dev/null)
    if echo "$body" | grep -q "$expect"; then
      echo "✅ ${host} routes to ${expect}"
      return 0
    fi
  done
  return 1
}

check_host "web-a.company.com" "hello from web-a" || fail "web-a.company.com is not routing to the web-a app yet. Create a Service for web-a and an Ingress rule for its host."
check_host "web-b.company.com" "hello from web-b" || fail "web-b.company.com is not routing to the web-b app yet. Create a Service for web-b and an Ingress rule for its host."

echo "✅ Both web apps are exposed correctly."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/_badge_check_2 <<'BADGE_CHECK_EOF_2'
#!/bin/bash
# Verify ftp-app is reachable over TCP:21 from outside the cluster via an L4 Service.
fail() { echo "❌ $1"; exit 0; }

# Find a Service in ns apps that targets the ftp-app pods on port 21 and is externally
# exposed (NodePort or LoadBalancer).
SVC_JSON=$(kubectl -n apps get svc -o json 2>/dev/null)

NODEPORT=$(echo "$SVC_JSON" | python3 - <<'PY' 2>/dev/null
import json,sys
data=json.load(sys.stdin)
for s in data.get("items",[]):
    spec=s.get("spec",{})
    if spec.get("type") not in ("NodePort","LoadBalancer"): continue
    if spec.get("selector",{}).get("app")!="ftp-app": continue
    for p in spec.get("ports",[]):
        tp=p.get("targetPort")
        if p.get("port")==21 or tp==21 or str(tp)=="21":
            if p.get("nodePort"):
                print(p["nodePort"]); sys.exit()
PY
)

[ -z "$NODEPORT" ] && fail "No externally-exposed Service (NodePort/LoadBalancer) targeting ftp-app port 21 found. An HTTP Ingress cannot carry FTP — expose it at L4."

# Confirm the port actually accepts a TCP connection.
if command -v nc >/dev/null 2>&1; then
  nc -z -w5 localhost "$NODEPORT" 2>/dev/null || fail "Service exists on nodePort ${NODEPORT} but the TCP connection failed. Check the Service selector and targetPort."
else
  timeout 5 bash -c "echo > /dev/tcp/localhost/${NODEPORT}" 2>/dev/null || fail "TCP connect to nodePort ${NODEPORT} failed. Check the Service selector and targetPort."
fi

echo "✅ ftp-app is reachable over TCP on nodePort ${NODEPORT}."
exit 0

BADGE_CHECK_EOF_2
chmod +x /usr/local/bin/_badge_check_2
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
/usr/local/bin/_badge_check_2
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
