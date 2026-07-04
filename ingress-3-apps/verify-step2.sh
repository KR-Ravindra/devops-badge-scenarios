#!/bin/bash
# Verify ftp-app is reachable over TCP:21 from outside the cluster via an L4 Service.
fail() { echo "❌ $1"; exit 1; }

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
