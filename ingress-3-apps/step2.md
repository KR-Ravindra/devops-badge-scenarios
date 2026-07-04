# Step 2 — Expose the FTP app

Now make **ftp-app** reachable over raw TCP on port **21** from outside the cluster.

```
kubectl -n apps get deploy ftp-app
```

> FTP is not HTTP. Ask yourself whether the ingress controller you used in Step 1 can carry this traffic — and if not, what kind of Service exposes an arbitrary TCP port to the outside.

When port 21 reaches the ftp-app from the node, click **Check**.

<details>
<summary>Hint</summary>

An HTTP Ingress can't route FTP. You need L4 exposure — a `Service` of type `NodePort` or `LoadBalancer` targeting port 21 (ingress-nginx can also do TCP via a `tcp-services` ConfigMap, but a plain L4 Service is the clean answer). Verify:

```
kubectl -n apps get svc
nc -zv localhost <nodePort>
```
</details>
