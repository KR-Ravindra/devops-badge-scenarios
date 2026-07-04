#!/bin/bash
set -e

# Install helm if missing.
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 || true
fi

CHART=/root/app-chart
mkdir -p "$CHART/templates"

cat > "$CHART/Chart.yaml" <<'EOF'
apiVersion: v2
name: myapp
description: Demo app chart
type: application
version: 0.1.0
appVersion: "1.0"
EOF

# Sensible defaults; env files override these.
cat > "$CHART/values.yaml" <<'EOF'
replicaCount: 1
image:
  repository: myapp
  tag: latest
EOF

cat > "$CHART/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-myapp
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels: { app: myapp }
  template:
    metadata:
      labels: { app: myapp }
    spec:
      containers:
        - name: myapp
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
EOF

# Empty env files for the candidate to fill.
for env in dev staging prod; do
  cat > "$CHART/values-$env.yaml" <<EOF
# Fill in the overrides for the $env environment.
EOF
done

touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Render the chart per environment and assert replicas + image tag.
fail() { echo "❌ $1"; exit 0; }
CHART=/root/app-chart

command -v helm >/dev/null 2>&1 || fail "helm is not available."

check_env() {
  local env="$1" want_replicas="$2" want_tag="$3"
  local vf="$CHART/values-$env.yaml"
  [ -f "$vf" ] || fail "$vf is missing."
  local out
  out=$(helm template "$env" "$CHART" -f "$vf" 2>/dev/null) || fail "helm template failed for $env — check YAML syntax in $vf."

  echo "$out" | grep -Eq "replicas:[[:space:]]*${want_replicas}\b" \
    || fail "$env should render replicas: ${want_replicas}. Fix replicaCount in $vf."
  echo "$out" | grep -Eq "image:[[:space:]]*\"?myapp:${want_tag}\"?" \
    || fail "$env should render image myapp:${want_tag}. Fix image.tag in $vf."
  echo "✅ $env → replicas ${want_replicas}, image myapp:${want_tag}"
}

check_env dev 1 dev
check_env staging 2 staging
check_env prod 5 prod

echo "✅ All three environments render correctly from one chart."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
