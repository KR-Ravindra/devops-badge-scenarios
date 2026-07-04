# Slim a Bloated Docker Image

`/root/app` contains a small Go web service and a `Dockerfile` that builds and runs
it. It **works**, but the image is enormous (~800 MB) because it ships the entire
Go toolchain in the final image.

Your job: rewrite the `Dockerfile` so that:

1. The image still builds and the app still serves on port **8080** (returns `hello from app`).
2. The final image is **under 50 MB**.

Don't change `main.go` — only the `Dockerfile`. Docker and the base images are
pre-pulled. Click **START**.
