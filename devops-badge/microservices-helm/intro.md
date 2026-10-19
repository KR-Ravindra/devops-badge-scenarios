# Deploy a Microservices App With Helm

Your team runs **Online Boutique**, a shop made of 11 services (10 application
services plus Redis for the carts). Today it is deployed with one big file of
plain Kubernetes manifests, applied by hand. You're asked to make it a proper,
repeatable, production-ready deployment.

What you have:

| | |
|---|---|
| Cluster | A Kubernetes cluster on this machine (k3s, one node, 2 vCPU). Admin kubeconfig: `/etc/rancher/k3s/k3s.yaml` (also at `~/.kube/config`) |
| Tools | `kubectl`, `helm` 3 (with the `helm-diff` plugin) and `helmfile` 1.x are installed |
| Code | `/root/online-boutique/config.yaml`: the current manifests (a git repo, branch `main`) |

This lab stands in for a managed cluster:

| In production | In this lab |
|---|---|
| Managed Kubernetes (e.g. EKS) with a cloud load balancer | k3s on one 2 vCPU VM; a `LoadBalancer` Service is published on port 80 of this machine (k3s ServiceLB), which is what the **shop link** opens |
| Images from `gcr.io/google-samples/microservices-demo` (course: `v0.8.0`) | The same images from `us-central1-docker.pkg.dev/google-samples/microservices-demo`, tag `v0.10.4` |

Facts about the environment:

- The `v0.10.4` images do **not** contain `/bin/grpc_health_probe`. The gRPC
  services implement the standard gRPC health service, so use Kubernetes'
  built-in `grpc:` probes (or `httpGet` for the frontend), not `exec` probes.
- The application images, `redis:alpine` and `redis:7.4-alpine` are already
  pulled onto the node.
- The node is small (2 vCPU): with 21 pods starting at once, expect probes to
  fail for the first half-minute or so before everything turns Ready.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.
