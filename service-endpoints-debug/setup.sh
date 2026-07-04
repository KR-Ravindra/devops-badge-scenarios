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
