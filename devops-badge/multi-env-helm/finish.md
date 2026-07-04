# Done

One chart, three environments — configuration comes from `values-<env>.yaml`
overrides layered over the chart defaults, not from copies of the chart.

**What this tests**

- Helm values precedence (`-f env-file` overrides `values.yaml`).
- Understanding that environment differences belong in values, not in forked charts.
- Bonus signal if the candidate mentions `--set`, `helm install/upgrade -f`, or a
  GitOps values-per-env layout.
