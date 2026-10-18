#!/bin/bash
# Reference solution: one generic chart for the 10 app services, a redis chart,
# per-service values, a helmfile. Used by CI to prove the scenario is solvable.
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd /root/online-boutique
mkdir -p charts/microservice/templates charts/redis/templates values

cat > charts/microservice/Chart.yaml <<'EOF'
apiVersion: v2
name: microservice
version: 0.1.0
EOF
cat > charts/microservice/values.yaml <<'EOF'
appName: ""
image: ""
replicas: 2
containerPort: 8080
servicePort: 8080
env: []
probe: {type: grpc, initialDelaySeconds: 10}
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits: {cpu: 300m, memory: 256Mi}
externalService: false
EOF
cat > charts/microservice/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels: {app: {{ .Values.appName }}}
  template:
    metadata:
      labels: {app: {{ .Values.appName }}}
    spec:
      containers:
      - name: server
        image: {{ .Values.image }}
        ports:
        - containerPort: {{ .Values.containerPort }}
        env:
        {{- range .Values.env }}
        - name: {{ .name }}
          value: {{ .value | quote }}
        {{- end }}
        {{- $p := .Values.probe }}
        {{- range $kind := list "readinessProbe" "livenessProbe" }}
        {{ $kind }}:
          initialDelaySeconds: {{ $p.initialDelaySeconds }}
          periodSeconds: 10
          {{- if eq $p.type "http" }}
          httpGet: {path: {{ $p.path }}, port: {{ $.Values.containerPort }}}
          {{- else }}
          grpc: {port: {{ $.Values.containerPort }}}
          {{- end }}
        {{- end }}
        resources: {{- toYaml .Values.resources | nindent 10 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}
spec:
  selector: {app: {{ .Values.appName }}}
  ports:
  - port: {{ .Values.servicePort }}
    targetPort: {{ .Values.containerPort }}
{{- if .Values.externalService }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}-external
spec:
  type: LoadBalancer
  selector: {app: {{ .Values.appName }}}
  ports:
  - port: 80
    targetPort: {{ .Values.containerPort }}
{{- end }}
EOF

cat > charts/redis/Chart.yaml <<'EOF'
apiVersion: v2
name: redis
version: 0.1.0
EOF
cat > charts/redis/templates/redis.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cart
spec:
  replicas: 1
  selector:
    matchLabels: {app: redis-cart}
  template:
    metadata:
      labels: {app: redis-cart}
    spec:
      containers:
      - name: redis
        image: redis:7.4-alpine
        ports:
        - containerPort: 6379
        readinessProbe: {tcpSocket: {port: 6379}, periodSeconds: 5}
        livenessProbe: {tcpSocket: {port: 6379}, periodSeconds: 5}
        resources:
          requests: {cpu: 50m, memory: 64Mi}
          limits: {cpu: 200m, memory: 256Mi}
        volumeMounts:
        - {name: redis-data, mountPath: /data}
      volumes:
      - {name: redis-data, emptyDir: {}}
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cart
spec:
  selector: {app: redis-cart}
  ports:
  - port: 6379
    targetPort: 6379
EOF

IMG=us-central1-docker.pkg.dev/google-samples/microservices-demo
v() { # name containerPort servicePort probe-yaml env-yaml...
  local n=$1 cp=$2 sp=$3 probe=$4; shift 4
  { echo "appName: $n"; echo "image: $IMG/$n:v0.10.4"; echo "containerPort: $cp"; echo "servicePort: $sp"
    echo "probe: $probe"; echo "env:"; echo "- {name: PORT, value: \"$cp\"}"
    for e in "$@"; do echo "- {name: ${e%%=*}, value: \"${e#*=}\"}"; done; } > values/$n.yaml
}
G='{type: grpc, initialDelaySeconds: 10}'
v currencyservice 7000 7000 "$G" DISABLE_PROFILER=1
v productcatalogservice 3550 3550 "$G" DISABLE_PROFILER=1
v shippingservice 50051 50051 "$G" DISABLE_PROFILER=1
v cartservice 7070 7070 "$G" REDIS_ADDR=redis-cart:6379
v emailservice 8080 5000 "$G" DISABLE_PROFILER=1
v paymentservice 50051 50051 "$G" DISABLE_PROFILER=1
v recommendationservice 8080 8080 "$G" PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 DISABLE_PROFILER=1
v adservice 9555 9555 '{type: grpc, initialDelaySeconds: 30}'
printf 'resources:\n  requests: {cpu: 50m, memory: 180Mi}\n  limits: {cpu: 300m, memory: 400Mi}\n' >> values/adservice.yaml
v checkoutservice 5050 5050 "$G" PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 \
  SHIPPING_SERVICE_ADDR=shippingservice:50051 PAYMENT_SERVICE_ADDR=paymentservice:50051 \
  EMAIL_SERVICE_ADDR=emailservice:5000 CURRENCY_SERVICE_ADDR=currencyservice:7000 CART_SERVICE_ADDR=cartservice:7070
v frontend 8080 80 '{type: http, path: /_healthz, initialDelaySeconds: 10}' \
  PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 CURRENCY_SERVICE_ADDR=currencyservice:7000 \
  CART_SERVICE_ADDR=cartservice:7070 RECOMMENDATION_SERVICE_ADDR=recommendationservice:8080 \
  SHIPPING_SERVICE_ADDR=shippingservice:50051 CHECKOUT_SERVICE_ADDR=checkoutservice:5050 \
  AD_SERVICE_ADDR=adservice:9555 SHOPPING_ASSISTANT_SERVICE_ADDR=shoppingassistantservice:80 \
  ENABLE_PROFILER=0
echo "externalService: true" >> values/frontend.yaml

{ echo "helmDefaults: {wait: true, timeout: 600}"
  echo "releases:"
  echo "- {name: redis-cart, namespace: microservices, createNamespace: true, chart: ./charts/redis}"
  for f in values/*.yaml; do n=$(basename $f .yaml)
    echo "- {name: $n, namespace: microservices, createNamespace: true, chart: ./charts/microservice, values: [$f]}"
  done; } > helmfile.yaml

kubectl create ns microservices --dry-run=client -o yaml | kubectl apply -f -
helmfile sync
