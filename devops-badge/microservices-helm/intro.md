# Deploy a Microservices App With Helm

Your team runs **Online Boutique**, a shop made of 11 services (10 application
services plus Redis for the carts). Today it is deployed with one big file of
plain Kubernetes manifests, applied by hand. You're asked to make it a proper,
repeatable, production-ready deployment.

What you have:

| | |
|---|---|
| Cluster | A Kubernetes cluster on this machine (k3s, one node). Admin kubeconfig: `/etc/rancher/k3s/k3s.yaml` |
| Tools | `kubectl`, `helm` (with the `helm-diff` plugin) and `helmfile` are installed |
| Code | `/root/online-boutique/config.yaml`: the current manifests (a git repo, branch `main`) |

The application images are already pulled onto the node.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.
