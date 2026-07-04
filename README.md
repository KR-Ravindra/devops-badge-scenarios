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

## Publishing

1. On killercoda.com → Creator dashboard → link this repo.
2. It detects each `*/index.json` as a scenario.
3. Set each scenario to **Unlisted**; make this GitHub repo **private** again.
4. Share the direct link with the candidate during a screen-shared session.

Reference patterns: `killercoda/scenario-examples` (forked at `k-r-ravindra/scenario-examples`).
