# Done

You exposed:

- **web-a** and **web-b** via Services + host-based **Ingress** rules (HTTP L7).
- **ftp-app** via an **L4 Service** (NodePort/LoadBalancer), because an HTTP Ingress can't carry FTP.

**What this scenario is really testing**

- Do you reach for Ingress for HTTP host routing, but recognise it stops at L7?
- Do you know non-HTTP protocols need a NodePort/LoadBalancer (or ingress-nginx TCP services), not an Ingress rule?
- Service → Deployment wiring: selectors and `targetPort` correct.
