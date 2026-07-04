# Step 1 — Expose the two web apps

Make **web-a** and **web-b** reachable over HTTP, each on its own hostname:

- `http://web-a.company.com` → `web-a` deployment (port 8080)
- `http://web-b.company.com` → `web-b` deployment (port 8080)

An NGINX ingress controller is already running in `ingress-nginx`.

Check the running apps:

```
kubectl -n apps get deploy,pods
```

You decide the resources. When both hostnames route to the right app, click **Check**.

<details>
<summary>Hint</summary>

HTTP host-based routing is exactly what Ingress is for. You'll need a Service in front of each Deployment, then an Ingress with a rule per host. Verify from inside the node with:

```
curl -H "Host: web-a.company.com" http://localhost/
```
</details>
