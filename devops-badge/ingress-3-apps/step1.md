# Step 1 — Expose the two web apps

Make **web-a** and **web-b** reachable over HTTP, each on its own hostname:

- `http://web-a.company.com` → `web-a` deployment (port 8080)
- `http://web-b.company.com` → `web-b` deployment (port 8080)

An NGINX ingress controller is already running in `ingress-nginx`.

Check the running apps:

```
kubectl -n apps get deploy,pods
```

You decide the resources. When both hostnames route to the right app, run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
