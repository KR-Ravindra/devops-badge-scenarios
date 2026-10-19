#!/bin/bash
# Course-faithful solution: the bootcamp's helm-chart-microservices repo
# (gitlab.com/twn-devops-bootcamp/latest/10-kubernetes/helm-chart-microservices @ 96f7129):
# charts/microservice + charts/redis with appName/appImage/appVersion/appReplicas/
# containerEnvVars values, values/<svc>-values.yaml, the same release names
# (rediscart, frontendservice, ...) and a helmfile.yaml. Probes and resources are
# carried over from the course's production-ready config.yaml (grpc: probes,
# periodSeconds 5). Lab deviations, all from the lab's own config.yaml / docs:
# v0.10.4 images, env vars from config.yaml, a pinned redis tag, CPU requests cut to
# fit the 2 vCPU node, and the namespace.
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd /root/online-boutique
mkdir -p charts/microservice/templates charts/redis/templates values

cat > charts/microservice/Chart.yaml <<'EOF'
apiVersion: v2
name: microservice
description: A Helm chart for Kubernetes
type: application
version: 0.1.0
appVersion: "1.16.0"
EOF
cat > charts/microservice/values.yaml <<'EOF'
appName: servicename
appImage: gcr.io/google-samples/microservices-demo/servicename
appVersion: v0.0.0
appReplicas: 1
containerPort: 8080
containerEnvVars:
- name: ENV_VAR_ONE
  value: "valueone"

servicePort: 8080
serviceType: ClusterIP
healthCheck: grpc
healthCheckPath: /_healthz
probeInitialDelaySeconds: 0
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
EOF
cat > charts/microservice/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
spec:
  replicas: {{ .Values.appReplicas }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
      - name: {{ .Values.appName }}
        image: "{{ .Values.appImage }}:{{ .Values.appVersion }}"
        ports:
        - containerPort: {{ .Values.containerPort }}
        env:
        {{- range .Values.containerEnvVars}}
        - name: {{ .name }}
          value: {{ .value | quote }}
        {{- end}}
        livenessProbe:
          {{- if eq .Values.healthCheck "http" }}
          httpGet:
            path: {{ .Values.healthCheckPath | quote }}
            port: {{ .Values.containerPort }}
          {{- else }}
          grpc:
            port: {{ .Values.containerPort }}
          {{- end }}
          initialDelaySeconds: {{ .Values.probeInitialDelaySeconds }}
          periodSeconds: 5
        readinessProbe:
          {{- if eq .Values.healthCheck "http" }}
          httpGet:
            path: {{ .Values.healthCheckPath | quote }}
            port: {{ .Values.containerPort }}
          {{- else }}
          grpc:
            port: {{ .Values.containerPort }}
          {{- end }}
          periodSeconds: 5
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
EOF
cat > charts/microservice/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}
spec:
  type: {{ .Values.serviceType }}
  selector:
    app: {{ .Values.appName }}
  ports:
  - protocol: TCP
    port: {{ .Values.servicePort }}
    targetPort: {{ .Values.containerPort }}
EOF

# charts/redis: the course chart verbatim, with a pinned image tag
cat > charts/redis/Chart.yaml <<'EOF'
apiVersion: v2
name: redis
description: A Helm chart for Kubernetes
type: application
version: 0.1.0
appVersion: "1.16.0"
EOF
cat > charts/redis/values.yaml <<'EOF'
appName: redis
appImage: redis
appVersion: 7.4-alpine
appReplicas: 1
containerPort: 6379
volumeName: redis-data
containerMountPath: /data

servicePort: 6379
EOF
cat > charts/redis/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
spec:
  replicas: {{ .Values.appReplicas }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
      - name: {{ .Values.appName }}
        image: "{{ .Values.appImage }}:{{ .Values.appVersion }}"
        ports:
        - containerPort: {{ .Values.containerPort }}
        livenessProbe:
          initialDelaySeconds: 5
          tcpSocket:
            port: {{ .Values.containerPort }}
          periodSeconds: 5
        readinessProbe:
          initialDelaySeconds: 5
          tcpSocket:
            port: {{ .Values.containerPort }}
          periodSeconds: 5
        resources:
          requests:
            cpu: 70m
            memory: 200Mi
          limits:
            cpu: 125m
            memory: 300Mi
        volumeMounts:
        - name: {{ .Values.volumeName }}
          mountPath: {{ .Values.containerMountPath }}
      volumes:
      - name: {{ .Values.volumeName }}
        emptyDir: {}
EOF
cat > charts/redis/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}
spec:
  type: ClusterIP
  selector:
    app: {{ .Values.appName }}
  ports:
  - protocol: TCP
    port: {{ .Values.servicePort }}
    targetPort: {{ .Values.containerPort }}
EOF

IMG=us-central1-docker.pkg.dev/google-samples/microservices-demo
# values/<file> appName containerPort servicePort [extra yaml lines] -- env NAME=VALUE...
vals() {
  local file=$1 n=$2 cp=$3 sp=$4; shift 4
  local extra=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do extra+=("$1"); shift; done
  shift
  { echo "appName: $n"; echo "appImage: $IMG/$n"; echo "appVersion: v0.10.4"; echo "appReplicas: 2"
    echo "containerPort: $cp"; echo "containerEnvVars:"
    for e in "$@"; do echo "- name: ${e%%=*}"; echo "  value: \"${e#*=}\""; done
    echo; echo "servicePort: $sp"
    for x in ${extra[@]+"${extra[@]}"}; do echo "$x"; done; } > values/$file
}
vals email-service-values.yaml emailservice 8080 5000 -- PORT=8080 DISABLE_PROFILER=1
vals cart-service-values.yaml cartservice 7070 7070 -- REDIS_ADDR=redis-cart:6379
vals currency-service-values.yaml currencyservice 7000 7000 -- PORT=7000 DISABLE_PROFILER=1
vals payment-service-values.yaml paymentservice 50051 50051 -- PORT=50051 DISABLE_PROFILER=1
vals recommendation-service-values.yaml recommendationservice 8080 8080 -- PORT=8080 \
  PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 DISABLE_PROFILER=1
vals productcatalog-service-values.yaml productcatalogservice 3550 3550 -- PORT=3550 DISABLE_PROFILER=1
vals shipping-service-values.yaml shippingservice 50051 50051 -- PORT=50051 DISABLE_PROFILER=1
# course config.yaml sizes adservice at 200m/180Mi -> 300m/300Mi; CPU request cut to fit the node
vals ad-service-values.yaml adservice 9555 9555 \
  'resources:' '  requests:' '    cpu: 100m' '    memory: 180Mi' '  limits:' '    cpu: 300m' '    memory: 300Mi' \
  'probeInitialDelaySeconds: '"${ADSERVICE_DELAY:-0}" -- PORT=9555
vals checkout-service-values.yaml checkoutservice 5050 5050 -- PORT=5050 \
  PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 SHIPPING_SERVICE_ADDR=shippingservice:50051 \
  PAYMENT_SERVICE_ADDR=paymentservice:50051 EMAIL_SERVICE_ADDR=emailservice:5000 \
  CURRENCY_SERVICE_ADDR=currencyservice:7000 CART_SERVICE_ADDR=cartservice:7070
vals frontend-values.yaml frontend 8080 80 'serviceType: LoadBalancer' 'healthCheck: http' -- PORT=8080 \
  PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 CURRENCY_SERVICE_ADDR=currencyservice:7000 \
  CART_SERVICE_ADDR=cartservice:7070 RECOMMENDATION_SERVICE_ADDR=recommendationservice:8080 \
  SHIPPING_SERVICE_ADDR=shippingservice:50051 CHECKOUT_SERVICE_ADDR=checkoutservice:5050 \
  AD_SERVICE_ADDR=adservice:9555 SHOPPING_ASSISTANT_SERVICE_ADDR=shoppingassistantservice:80 ENABLE_PROFILER=0
printf 'appName: redis-cart\nappReplicas: 2\n' > values/redis-values.yaml

# helmfile.yaml: the course file, plus the target namespace
cat > helmfile.yaml <<'EOF'
releases:
  - name: rediscart
    namespace: microservices
    chart: charts/redis
    values:
      - values/redis-values.yaml
      - appReplicas: "1"
      - volumeName: "redis-cart-data"
EOF
for r in emailservice:email-service cartservice:cart-service currencyservice:currency-service \
         paymentservice:payment-service recommendationservice:recommendation-service \
         productcatalogservice:productcatalog-service shippingservice:shipping-service \
         adservice:ad-service checkoutservice:checkout-service frontendservice:frontend; do
  printf '\n  - name: %s\n    namespace: microservices\n    chart: charts/microservice\n    values:\n      - values/%s-values.yaml\n' \
    "${r%%:*}" "${r#*:}" >> helmfile.yaml
done

kubectl create namespace microservices --dry-run=client -o yaml | kubectl apply -f -
helmfile sync
