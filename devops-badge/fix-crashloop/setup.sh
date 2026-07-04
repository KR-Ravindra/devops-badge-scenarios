#!/bin/bash
set -e
# Fault: image tag does not exist -> ImagePullBackOff, pods never Ready.
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels: { app: api }
spec:
  replicas: 2
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: api
          image: nginx:1.25-this-tag-does-not-exist
          ports: [ { containerPort: 80 } ]
EOF
touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Pass when the api deployment is fully available.
fail() { echo "❌ $1"; exit 0; }

D=$(kubectl get deploy api -o json 2>/dev/null) || fail "Deployment 'api' not found."
want=$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["spec"]["replicas"])' 2>/dev/null)
ready=$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",{}).get("readyReplicas",0))' 2>/dev/null)

if [ "${ready:-0}" -ge "${want:-1}" ] 2>/dev/null && [ "${ready:-0}" -ge 1 ]; then
  echo "✅ api is Ready (${ready}/${want} replicas)."
  exit 0
fi

reason=$(kubectl get pods -l app=api -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
fail "api is not Ready yet (${ready:-0}/${want:-?}). Pod state: ${reason:-not scheduled}. Check the image reference."

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
