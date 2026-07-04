# Step 1 — Extract the shared logic

In `/root/ci` there are two build scripts:

```
build-service-a.sh
build-service-b.sh
```

They are almost identical — the **install → test → package** stages are copy-pasted
and only the service name differs. Refactor them so the common stages live in **one
shared library** that both scripts use (DRY). You choose the mechanism (a sourced
`lib/*.sh`, functions taking the service as a parameter, etc.).

Requirements you'll be graded on:

1. Both `build-service-a.sh` and `build-service-b.sh` still run successfully and
   produce their `.deps`, `.tests` and `.artifact` files in `/root/ci/out`.
2. A **shared file** exists that both build scripts pull in (e.g. via `source`).
3. The per-service scripts are thin — the duplicated stage logic is gone from them.

When done, run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
