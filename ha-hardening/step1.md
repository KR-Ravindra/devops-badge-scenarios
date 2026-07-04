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

When done, click **Check**.

<details>
<summary>Hint</summary>

Bump `spec.replicas` to 3, add a `readinessProbe` (httpGet path `/` port 8080),
add `topologySpreadConstraints` with `topologyKey: kubernetes.io/hostname`, and
create a PDB:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: payments, namespace: prod }
spec:
  minAvailable: 2
  selector: { matchLabels: { app: payments } }
```
</details>
