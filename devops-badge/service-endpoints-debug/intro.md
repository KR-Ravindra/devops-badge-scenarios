# The Service Has No Endpoints

In the `default` namespace there's a Deployment `orders` (3 healthy pods) and a
Service `orders`. But nothing can reach the app through the Service:

```
kubectl get deploy,pods -l app=orders
kubectl get svc orders
kubectl get endpoints orders          # <-- notice anything?
```

The pods are fine. The Service is the problem. **Fix the Service so it actually
routes to the `orders` pods** (its endpoints should list the pod IPs).

`kubectl` is available. Click **START**.
