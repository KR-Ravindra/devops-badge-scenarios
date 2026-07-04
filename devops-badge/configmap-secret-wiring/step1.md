# Step 1 — Inject the config and secret

Make the running `webconf` pod expose:

- `APP_COLOR=blue` — sourced from a ConfigMap `app-config`
- `API_KEY=s3cr3t` — sourced from a Secret `app-secret`

Verify inside the pod:

```
kubectl exec deploy/webconf -- printenv APP_COLOR API_KEY
```

Both must print the right values, sourced from the ConfigMap/Secret (not hardcoded).
Then run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
