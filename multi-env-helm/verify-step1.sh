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
