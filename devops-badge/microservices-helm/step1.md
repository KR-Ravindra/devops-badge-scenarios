# Ship Online Boutique with Helm

Deploy all 11 services into the namespace `microservices`, managed by Helm:

1. The 10 application services are deployed from **one reusable chart** that you
   write, configured per service through values. Redis may use its own chart.
   Every service, including Redis, runs as a **Deployment** with the name it has
   in `config.yaml` (`redis-cart` for Redis).
2. A helmfile in `/root/online-boutique` (`helmfile.yaml` or
   `helmfile.yaml.gotmpl`) declares every release, so the whole shop can be
   deployed with one command.
3. Every container follows production basics:
   - its image is pinned to a version (a tag with a version number, or a digest),
   - it has a liveness probe and a readiness probe,
   - it has CPU and memory requests and limits.
4. Each application service runs at least **2 replicas**. Redis runs 1.
5. The shop must work for a customer: it answers on **port 80** of this machine
   through a `LoadBalancer` Service, and browsing, adding to the cart and
   checking out all go through.

Keep the service names and ports from `config.yaml`, since the services find
each other by them. The cluster is a single node with 2 vCPU: check what it can
hold (`kubectl describe node`) when you size your requests, and expect startup
to be slow when everything starts at once.

[Open the shop]({{TRAFFIC_HOST1_80}}) once it is deployed.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.
