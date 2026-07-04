# Step 1 — Get the Service routing to pods

The Service currently has **no endpoints**, so traffic goes nowhere. Find out why
the Service isn't selecting the running pods, and fix it.

```
kubectl describe svc orders          # what selector is it using?
kubectl get pods -l app=orders --show-labels   # what labels do the pods have?
kubectl get endpoints orders         # should list pod IPs once fixed
```

When `kubectl get endpoints orders` shows the pod IPs, run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
