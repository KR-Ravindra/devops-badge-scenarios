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
