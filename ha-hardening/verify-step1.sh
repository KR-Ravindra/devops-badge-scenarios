#!/bin/bash
# Grade four HA criteria on the payments deployment.
fail() { echo "❌ $1"; exit 1; }
NS=prod; DEP=payments

D=$(kubectl -n $NS get deploy $DEP -o json 2>/dev/null) || fail "Deployment $DEP not found in $NS."

# 1) Replicas >= 3
reps=$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["spec"]["replicas"])' 2>/dev/null)
[ "${reps:-0}" -ge 3 ] 2>/dev/null || fail "replicas is ${reps:-?}; set at least 3 for pod-level resilience."

# 2) PodDisruptionBudget selecting app=payments with a budget field set
pdb=$(kubectl -n $NS get pdb -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for p in d.get("items",[]):
    sel=p.get("spec",{}).get("selector",{}).get("matchLabels",{})
    if sel.get("app")=="payments" and ("minAvailable" in p["spec"] or "maxUnavailable" in p["spec"]):
        print("ok"); break
' 2>/dev/null)
[ "$pdb" = "ok" ] || fail "No PodDisruptionBudget selecting app=payments with minAvailable/maxUnavailable. Add one to survive node drains."

# 3) Spread: podAntiAffinity OR topologySpreadConstraints on hostname
spread=$(echo "$D" | python3 -c '
import json,sys
spec=json.load(sys.stdin)["spec"]["template"]["spec"]
ok=False
tsc=spec.get("topologySpreadConstraints",[])
if any(c.get("topologyKey")=="kubernetes.io/hostname" for c in tsc): ok=True
aff=spec.get("affinity",{}).get("podAntiAffinity",{})
terms=aff.get("requiredDuringSchedulingIgnoredDuringExecution",[]) or []
terms+= [t.get("podAffinityTerm",{}) for t in aff.get("preferredDuringSchedulingIgnoredDuringExecution",[]) or []]
if any(t.get("topologyKey")=="kubernetes.io/hostname" for t in terms): ok=True
print("ok" if ok else "no")
' 2>/dev/null)
[ "$spread" = "ok" ] || fail "No spread across nodes. Add topologySpreadConstraints or podAntiAffinity on kubernetes.io/hostname."

# 4) readinessProbe present
probe=$(echo "$D" | python3 -c '
import json,sys
c=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0]
print("ok" if c.get("readinessProbe") else "no")
' 2>/dev/null)
[ "$probe" = "ok" ] || fail "No readinessProbe on the container. Add one so unhealthy pods are pulled from rotation."

# Sanity: at least 2 replicas actually available
avail=$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",{}).get("availableReplicas",0))' 2>/dev/null)
[ "${avail:-0}" -ge 2 ] 2>/dev/null || fail "Only ${avail:-0} replicas are available. Make sure the pods actually schedule and pass readiness."

echo "✅ replicas≥3, PDB set, node spread configured, readiness probe present, ≥2 available."
exit 0
