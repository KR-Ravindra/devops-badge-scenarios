# DevOps Badge Scenarios (KillerCoda)

Ten hands-on assessment scenarios for the internal DevOps badge. Candidates
**solve** a broken/empty environment instead of answering verbal questions. Each
scenario auto-grades via `verify-*.sh`.

> **Visibility:** currently **public** for easy testing/import. Flip back to
> **private** before real use — the `verify-*.sh` scripts contain grading logic and
> expected answers. On KillerCoda, set each scenario to **Unlisted** so it's
> link-only and not discoverable.

See **[EVALUATION.md](EVALUATION.md)** for the full rubric (auto-pass criteria +
weak/solid/strong scoring guidance per scenario).

## Scenarios

| Dir | Source Q | Skills tested | Backend | Difficulty |
|-----|----------|---------------|---------|------------|
| `ingress-3-apps` | Q9 | Services, Ingress L7 vs L4 for non-HTTP | k8s 1-node | Medium |
| `multi-env-helm` | Q4 | Helm values precedence, per-env config | k8s 1-node | Medium |
| `debug-container-vm` | Q10 | Container/port troubleshooting on a VM | ubuntu | Low–Med |
| `ha-hardening` | Q6 | HA: replicas, PDB, spread, probes | k8s 2-node | High |
| `fix-crashloop` | — | Core k8s debugging (pod state/events) | k8s 1-node | Low–Med |
| `shared-pipeline-library` | Q3 | DRY / shared pipeline design | ubuntu | Medium |
| `private-registry` | Q7 | Artifact/registry management | ubuntu | Low–Med |
| `dockerfile-multistage` | — | Multi-stage builds, image hygiene | ubuntu | Medium |
| `configmap-secret-wiring` | — | ConfigMaps, Secrets, env injection | k8s 1-node | Low–Med |
| `service-endpoints-debug` | — | Service selectors/endpoints debugging | k8s 1-node | Medium |

Design-only questions kept verbal (not simulated): **Q8** (multi-region AWS) and the
cluster-level tier of **Q6**. **Q1/Q2** dropped as low-signal.

## KillerCoda format (per scenario dir)

- `index.json` — scenario definition: intro, steps (each with a `verify` script), finish, backend image.
- `intro.md` / `step*.md` / `finish.md` — markdown shown to the candidate.
- `setup.sh` — background script that seeds the environment (referenced as `intro.background`).
- `verify-*.sh` — grading script per step; exit `0` = pass, non-zero = fail (last line shown to candidate).

## Arrangement — a Course

The 10 scenarios are ordered `01 … 10` in their titles (easy Docker warm-up →
k8s debugging → Helm/CI → HA capstone, domains interleaved). Group them into a
single **Course** so a candidate walks the whole badge start-to-finish from one URL.

> A KillerCoda **Course is created in the dashboard**, not from a repo file:
> Creator profile → **Courses** → **New course** → add the 10 scenarios in title
> order → save. The repo stays as 10 scenarios; the course just wraps them.

## Publishing

1. On killercoda.com → Creator dashboard → link this repo (detects each `*/index.json`).
2. Build the **Course** (above) in title order.
3. Set each scenario / the course to **Unlisted**; make this GitHub repo **private** again.
4. Share the course link with the candidate during a screen-shared session.

## Future work

Rebalance away from the current Kubernetes-heavy mix (6/10) to cover the full DevOps
spectrum — Terraform/LocalStack (IaC), Ansible (config mgmt), Prometheus
(observability), a real CI pipeline, Git, and Linux troubleshooting — cutting k8s to
~3. All fit a single Ubuntu VM (k3s + docker + tooling). Tracked in agent-works.

Reference patterns: `killercoda/scenario-examples` (forked at `k-r-ravindra/scenario-examples`).
