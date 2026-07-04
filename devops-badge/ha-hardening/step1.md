# Step 1 — Harden `payments`

Make the Deployment resilient. You'll be graded on four things:

1. **Replicas** — at least **3**.
2. **PodDisruptionBudget** — a PDB in `prod` selecting `app=payments`, with
   `minAvailable` (or `maxUnavailable`) set so a drain can't take everything.
3. **Spread** — `podAntiAffinity` or `topologySpreadConstraints` across
   `kubernetes.io/hostname`, so replicas don't all land on one node.
4. **Health probe** — a `readinessProbe` on the container (port 8080).

Useful commands:

```
kubectl -n prod get deploy payments -o yaml
kubectl -n prod get pdb
kubectl -n prod get pods -o wide     # confirm pods land on different nodes
```

When done, run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
