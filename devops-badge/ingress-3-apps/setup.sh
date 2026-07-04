#!/bin/bash
# Background setup: seed 3 healthy-but-unexposed deployments. No Services, no Ingress.
set -e

kubectl create namespace apps >/dev/null 2>&1 || true

# Two HTTP web apps (echo server on 8080).
for app in web-a web-b; do
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app}
  namespace: apps
  labels: { app: ${app} }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${app} } }
  template:
    metadata: { labels: { app: ${app} } }
    spec:
      containers:
      - name: web
        image: hashicorp/http-echo:1.0
        args: ["-text=hello from ${app}", "-listen=:8080"]
        ports: [ { containerPort: 8080 } ]
EOF
done

# FTP app (TCP:21). vsftpd-style container; any TCP listener on 21 is fine for grading.
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ftp-app
  namespace: apps
  labels: { app: ftp-app }
spec:
  replicas: 1
  selector: { matchLabels: { app: ftp-app } }
  template:
    metadata: { labels: { app: ftp-app } }
    spec:
      containers:
      - name: ftp
        image: alpine:3.20
        command: ["/bin/sh","-c","apk add --no-cache socat >/dev/null 2>&1; socat TCP-LISTEN:21,reuseaddr,fork SYSTEM:'echo 220 fake-ftp ready'"]
        ports: [ { containerPort: 21 } ]
EOF

kubectl -n apps rollout status deploy/web-a --timeout=120s >/dev/null 2>&1 || true
kubectl -n apps rollout status deploy/web-b --timeout=120s >/dev/null 2>&1 || true
kubectl -n apps rollout status deploy/ftp-app --timeout=120s >/dev/null 2>&1 || true

# Signal readiness for KillerCoda step verification pattern.
touch /tmp/setup-done
