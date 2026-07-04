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
