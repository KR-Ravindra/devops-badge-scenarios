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
