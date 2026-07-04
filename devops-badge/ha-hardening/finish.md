# Done

`payments` now survives disruption:

- **Pod level** — multiple replicas + readiness probe keep the service up when a pod dies.
- **Node level** — spread across hostnames + a PodDisruptionBudget mean a drain
  can't evict every pod at once.

**What this tests**

- The pod/node/cluster HA mental model (this scenario covers pod + node; cluster-level
  = multi-cluster/multi-AZ is the design follow-up).
- Knowing PDBs guard *voluntary* disruptions (drains/upgrades), not crashes.
- Strong candidates explain the difference between `requiredDuringScheduling`
  anti-affinity (hard) and `preferred`/`topologySpreadConstraints` (soft) and why
  that matters on a small cluster.
