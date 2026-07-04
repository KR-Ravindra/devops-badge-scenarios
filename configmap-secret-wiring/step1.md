# Step 1 — Inject the config and secret

Make the running `webconf` pod expose:

- `APP_COLOR=blue` — sourced from a ConfigMap `app-config`
- `API_KEY=s3cr3t` — sourced from a Secret `app-secret`

Verify inside the pod:

```
kubectl exec deploy/webconf -- printenv APP_COLOR API_KEY
```

Both must print the right values, sourced from the ConfigMap/Secret (not hardcoded).
Then click **Check**.