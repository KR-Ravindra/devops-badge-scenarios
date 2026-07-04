# Get a Broken Deployment Healthy

The `api` Deployment in the `default` namespace was just rolled out, but it never
becomes Ready:

```
kubectl get deploy api
kubectl get pods -l app=api
```

The pods are not running. **Find out why and fix the Deployment so it rolls out
to a healthy, Ready state.**

Don't just delete and recreate blindly — diagnose it first. Click **START**.
