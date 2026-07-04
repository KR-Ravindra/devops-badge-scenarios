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
