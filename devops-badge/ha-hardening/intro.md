# Make a Critical App Survive Failure

The `payments` Deployment in namespace `prod` is business-critical, but it's
fragile: **1 replica, no health checks, no disruption protection, no spread.**
A single pod restart or a node drain takes the whole service down.

This is a 2-node cluster. Harden `payments` so it stays available when:

1. **A pod dies** — the service should not drop to zero.
2. **A node is drained** — a voluntary disruption should not evict every pod at once,
   and pods should be spread so they don't all sit on one node.

You can edit the live Deployment (`kubectl edit`) or apply new manifests. `helm`
and `kubectl` are available. Click **START**.
