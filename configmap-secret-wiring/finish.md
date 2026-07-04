# Done

Non-secret config comes from a ConfigMap, the credential from a Secret, and both
are injected as env vars via `valueFrom` — config decoupled from the image.

**What this tests**

- ConfigMap vs Secret: which data belongs where.
- `valueFrom`/`envFrom` injection and that pods pick up changes on restart.
- Strong candidates note Secrets are only base64 (not encrypted at rest by default),
  and mention mounting as files vs env, or external secret stores, for real workloads.
