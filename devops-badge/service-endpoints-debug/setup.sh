#!/bin/bash
set -e
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  labels: { app: orders }
spec:
  replicas: 3
  selector:
    matchLabels: { app: orders }
  template:
    metadata:
      labels: { app: orders }
    spec:
      containers:
        - name: orders
          image: hashicorp/http-echo:1.0
          args: ["-text=orders ok", "-listen=:8080"]
          ports: [ { containerPort: 8080 } ]
---
apiVersion: v1
kind: Service
metadata:
  name: orders
spec:
  selector:
    app: order          # BUG: typo, no pod has this label -> empty endpoints
  ports:
    - port: 8080
      targetPort: 8080
EOF
kubectl rollout status deploy/orders --timeout=120s >/dev/null 2>&1 || true
touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Pass when the orders Service has endpoints (selects the pods) on port 8080.
fail() { echo "❌ $1"; exit 0; }

kubectl get svc orders >/dev/null 2>&1 || fail "Service 'orders' not found — don't delete it, fix its selector."

# Count endpoint addresses.
n=$(kubectl get endpoints orders -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
c=0
for s in d.get("subsets",[]) or []:
    c += len(s.get("addresses",[]) or [])
print(c)
' 2>/dev/null)

[ "${n:-0}" -ge 1 ] 2>/dev/null || fail "Service 'orders' has no endpoints. Its selector must match the pod labels (app=orders)."

# Confirm it forwards to the app port.
port=$(kubectl get svc orders -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
[ "$port" = "8080" ] || fail "Service endpoints exist but targetPort is '${port}', not 8080. Point it at the container port."

echo "✅ Service 'orders' now has ${n} endpoint(s) on port 8080."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
