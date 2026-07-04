# Stand Up a Private Artifact Registry

Teams in your company keep rebuilding and re-downloading the same internal images
from the public internet. You want a **central, private registry** everyone
publishes to and pulls from.

On this VM, using Docker:

1. Run a **private container registry** listening on `localhost:5000`.
2. Publish an internal image to it as `localhost:5000/internal/app:1.0`.
3. Prove it's really in the registry (it should show up in the registry catalog).

A base image `alpine:3.20` is already pulled locally for you to repackage. Docker
is installed. Click **START**.
