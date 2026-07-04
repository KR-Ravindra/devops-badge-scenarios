# One Chart, Three Environments

A Helm chart for an app lives at `/root/app-chart`. You must deploy the **same
chart** to three environments, each with different configuration — **without
duplicating the chart**.

| Environment | Replicas | Image tag        |
|-------------|----------|------------------|
| dev         | 1        | `myapp:dev`      |
| staging     | 2        | `myapp:staging`  |
| prod        | 5        | `myapp:prod`     |

The chart's `deployment.yaml` is already templated to read `replicaCount` and
`image.tag` from values. Three environment values files exist but are empty:

```
app-chart/values-dev.yaml
app-chart/values-staging.yaml
app-chart/values-prod.yaml
```

Fill them so that rendering the chart with each file produces the right replica
count and image tag. `helm` is installed. Click **START**.
