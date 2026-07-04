# Expose 3 Apps From Kubernetes

The cluster is running three applications in the `apps` namespace, all healthy but **not reachable from outside the cluster**:

| App        | Deployment   | Container port | Protocol   | Must be reachable as        |
|------------|--------------|----------------|------------|-----------------------------|
| Web app A  | `web-a`      | 8080           | HTTP       | `http://web-a.company.com`  |
| Web app B  | `web-b`      | 8080           | HTTP       | `http://web-b.company.com`  |
| File share | `ftp-app`    | 21             | FTP (TCP)  | TCP port `21` from outside  |

An NGINX **ingress controller** is already installed in the `ingress-nginx` namespace.

Your job over the next two steps:

1. Expose **web-a** and **web-b** so each answers on its own hostname.
2. Expose **ftp-app** so it is reachable over raw TCP from outside the cluster.

> Think about *which* Kubernetes resources fit HTTP hostnames vs. a non-HTTP TCP protocol. They are not the same.

Setup takes ~30s to seed the deployments. When the terminal is ready, click **START**.
