# Done

The Service selector (`app: order`) didn't match the pod labels (`app: orders`),
so its endpoints list was empty and traffic had nowhere to go. Fixing the selector
populates the endpoints.

**What this tests**

- The Service → Endpoints → Pod chain, and that `kubectl get endpoints` is the fast
  way to prove a Service selects pods.
- Distinguishing a selector/label mismatch from a `targetPort` mismatch or an
  unhealthy pod — all present as "can't reach the service" but need different fixes.
- Strong candidates check labels and endpoints first instead of restarting things.
