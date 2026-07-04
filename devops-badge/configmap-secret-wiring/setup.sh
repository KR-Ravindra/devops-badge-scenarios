#!/bin/bash
set -e
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webconf
  labels: { app: webconf }
spec:
  replicas: 1
  selector:
    matchLabels: { app: webconf }
  template:
    metadata:
      labels: { app: webconf }
    spec:
      containers:
        - name: webconf
          image: busybox:1.36
          command: ["/bin/sh","-c","echo running; sleep 3600"]
EOF
kubectl rollout status deploy/webconf --timeout=120s >/dev/null 2>&1 || true
touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Grade: CM + Secret exist, deployment sources them, pod env is correct.
fail() { echo "❌ $1"; exit 0; }

# 1) ConfigMap value
cmv=$(kubectl get configmap app-config -o jsonpath='{.data.APP_COLOR}' 2>/dev/null)
[ "$cmv" = "blue" ] || fail "ConfigMap app-config must have APP_COLOR=blue (got '${cmv:-missing}')."

# 2) Secret value (base64-decoded)
sev=$(kubectl get secret app-secret -o jsonpath='{.data.API_KEY}' 2>/dev/null | base64 -d 2>/dev/null)
[ "$sev" = "s3cr3t" ] || fail "Secret app-secret must have API_KEY=s3cr3t (got '${sev:-missing}')."

# 3) Deployment sources them from the CM/Secret (not hardcoded)
srcs=$(kubectl get deploy webconf -o json 2>/dev/null | python3 -c '
import json,sys
c=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0]
cm=sec=False
for e in c.get("env",[]) or []:
    vf=e.get("valueFrom",{}) or {}
    if vf.get("configMapKeyRef"): cm=True
    if vf.get("secretKeyRef"): sec=True
for ef in c.get("envFrom",[]) or []:
    if ef.get("configMapRef"): cm=True
    if ef.get("secretRef"): sec=True
print(f"{cm}:{sec}")
' 2>/dev/null)
[ "$srcs" = "True:True" ] || fail "The container must source APP_COLOR from the ConfigMap and API_KEY from the Secret (use valueFrom/envFrom, not literal values)."

# 4) Actual pod env
env=$(kubectl exec deploy/webconf -- /bin/sh -c 'printf "%s|%s" "$APP_COLOR" "$API_KEY"' 2>/dev/null)
[ "$env" = "blue|s3cr3t" ] || fail "Pod env is '${env:-empty}'; expected APP_COLOR=blue and API_KEY=s3cr3t. Did the pod restart with the new env?"

echo "✅ ConfigMap + Secret created and injected; pod has APP_COLOR=blue, API_KEY=s3cr3t."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
