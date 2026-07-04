#!/bin/bash
# Verify web-a and web-b are reachable through the ingress controller by host header.
# Grades behaviour (does it route?), not the exact YAML the candidate wrote.

fail() { echo "❌ $1"; exit 0; }

# Resolve the ingress controller's in-cluster entry point. On kubeadm-1node the
# controller is typically reachable on the node via a NodePort or hostPort :80.
INGRESS_PORT=$(kubectl -n ingress-nginx get svc -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
INGRESS_PORT=${INGRESS_PORT:-80}

check_host() {
  local host="$1" expect="$2"
  # Try NodePort first, then plain :80 (hostPort/hostNetwork controllers).
  for url in "http://localhost:${INGRESS_PORT}/" "http://localhost/"; do
    body=$(curl -s --max-time 5 -H "Host: ${host}" "$url" 2>/dev/null)
    if echo "$body" | grep -q "$expect"; then
      echo "✅ ${host} routes to ${expect}"
      return 0
    fi
  done
  return 1
}

check_host "web-a.company.com" "hello from web-a" || fail "web-a.company.com is not routing to the web-a app yet. Create a Service for web-a and an Ingress rule for its host."
check_host "web-b.company.com" "hello from web-b" || fail "web-b.company.com is not routing to the web-b app yet. Create a Service for web-b and an Ingress rule for its host."

echo "✅ Both web apps are exposed correctly."
exit 0
