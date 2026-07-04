#!/bin/bash
# Pass when the api deployment is fully available.
fail() { echo "❌ $1"; exit 1; }

D=$(kubectl get deploy api -o json 2>/dev/null) || fail "Deployment 'api' not found."
want=$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["spec"]["replicas"])' 2>/dev/null)
ready=$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",{}).get("readyReplicas",0))' 2>/dev/null)

if [ "${ready:-0}" -ge "${want:-1}" ] 2>/dev/null && [ "${ready:-0}" -ge 1 ]; then
  echo "✅ api is Ready (${ready}/${want} replicas)."
  exit 0
fi

reason=$(kubectl get pods -l app=api -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
fail "api is not Ready yet (${ready:-0}/${want:-?}). Pod state: ${reason:-not scheduled}. Check the image reference."
