# Wire Config and Secrets Into a Pod

The `webconf` Deployment (namespace `default`) expects two environment variables,
but they're not set — so it runs with neither:

| Env var     | Value      | Must come from                        |
|-------------|------------|---------------------------------------|
| `APP_COLOR` | `blue`     | a **ConfigMap** named `app-config`    |
| `API_KEY`   | `s3cr3t`   | a **Secret** named `app-secret`       |

Create the ConfigMap and the Secret, and wire them into the Deployment's container
as those env vars. **Don't hardcode the values directly** in the pod spec — they
must be sourced from the ConfigMap and the Secret.

`kubectl` is available. Click **START**.
