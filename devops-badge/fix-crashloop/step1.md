# Step 1 — Make it Ready

Diagnose before you touch anything:

```
kubectl get pods -l app=api
kubectl describe pod -l app=api | tail -n 20    # look at Events
```

The pod status and events tell you exactly what's wrong. Fix the Deployment so
all replicas reach **Ready**, then click **Check**.