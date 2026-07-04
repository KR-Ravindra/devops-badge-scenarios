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

<details>
<summary>Hint</summary>

```
kubectl create configmap app-config --from-literal=APP_COLOR=blue
kubectl create secret generic app-secret --from-literal=API_KEY=s3cr3t
```

Then add to the container spec:

```yaml
env:
  - name: APP_COLOR
    valueFrom: { configMapKeyRef: { name: app-config, key: APP_COLOR } }
  - name: API_KEY
    valueFrom: { secretKeyRef: { name: app-secret, key: API_KEY } }
```

The pod restarts with the new env.
</details>
