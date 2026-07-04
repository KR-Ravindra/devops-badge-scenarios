# Step 1 — Per-environment rendering

Edit the three files so each renders the correct config:

- `app-chart/values-dev.yaml` → 1 replica, `myapp:dev`
- `app-chart/values-staging.yaml` → 2 replicas, `myapp:staging`
- `app-chart/values-prod.yaml` → 5 replicas, `myapp:prod`

Check your work with:

```
helm template dev ./app-chart -f ./app-chart/values-dev.yaml
helm template prod ./app-chart -f ./app-chart/values-prod.yaml
```

Confirm the `replicas:` and `image:` lines match the table, then click **Check**.