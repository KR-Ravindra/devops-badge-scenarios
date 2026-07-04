#!/bin/bash
set -e
kubectl create namespace prod >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments
  namespace: prod
  labels: { app: payments }
spec:
  replicas: 1
  selector:
    matchLabels: { app: payments }
  template:
    metadata:
      labels: { app: payments }
    spec:
      containers:
        - name: payments
          image: hashicorp/http-echo:1.0
          args: ["-text=payments ok", "-listen=:8080"]
          ports: [ { containerPort: 8080 } ]
EOF

kubectl -n prod rollout status deploy/payments --timeout=120s >/dev/null 2>&1 || true
touch /tmp/setup-done
