# Step 1 — Make it Ready

Diagnose before you touch anything:

```
kubectl get pods -l app=api
kubectl describe pod -l app=api | tail -n 20    # look at Events
```

The pod status and events tell you exactly what's wrong. Fix the Deployment so
all replicas reach **Ready**, then run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
