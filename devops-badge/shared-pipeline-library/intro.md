# Refactor Duplicated Pipelines Into a Shared Library

Two services each have a build script under `/root/ci`:

```
build-service-a.sh
build-service-b.sh
```

Both run the same **install → test → package** stages — the logic is copy-pasted
and only the service name differs. When a stage needs to change, someone has to edit
it in every script and inevitably misses one.

Refactor so the common stages live in **one shared library** that both scripts use,
without breaking either build. Click **START**.
