# DevOps Badge — Evaluation Guide

Ten hands-on scenarios. Each one auto-grades a **pass/fail** via its `verify-*.sh`
(the ✅/❌ the candidate sees). But the badge decision should use **more than
pass/fail** — watch *how* they solve it. For each scenario below:

- **Auto-pass** = the objective bar the grader enforces.
- **Weak / Solid / Strong** = what to look for while observing, for the badge score.

Suggested overall bar: **7/10 auto-passes**, with at least Solid on the two High
scenarios (`ha-hardening`, and the design follow-up on multi-region — see note).

| # | Scenario | Source Q | Skills | Difficulty | Time |
|---|----------|----------|--------|------------|------|
| 1 | `ingress-3-apps` | Q9 | Services, Ingress L7 vs L4 for non-HTTP | Medium | 15 min |
| 2 | `multi-env-helm` | Q4 | Helm values precedence, per-env config | Medium | 12 min |
| 3 | `debug-container-vm` | Q10 | Container/port troubleshooting on a VM | Low–Med | 10 min |
| 4 | `ha-hardening` | Q6 | HA: replicas, PDB, spread, probes | High | 20 min |
| 5 | `fix-crashloop` | — | Core k8s debugging (pod state/events) | Low–Med | 8 min |
| 6 | `shared-pipeline-library` | Q3 | DRY / shared pipeline design | Medium | 15 min |
| 7 | `private-registry` | Q7 | Artifact/registry management | Low–Med | 10 min |
| 8 | `dockerfile-multistage` | — | Multi-stage builds, image hygiene | Medium | 12 min |
| 9 | `configmap-secret-wiring` | — | ConfigMaps, Secrets, env injection | Low–Med | 10 min |
| 10 | `service-endpoints-debug` | — | Service selectors/endpoints debugging | Medium | 10 min |

> **Design-only questions (not simulated):** Q8 (multi-region AWS architecture) and
> the cluster-level tier of Q6 (multi-cluster/multi-AZ) don't fit a single-node lab.
> Keep those as whiteboard/verbal questions alongside this badge. Q1/Q2 were dropped
> (low signal per the review).

---

## 1. ingress-3-apps (Q9)
**Auto-pass:** web-a/web-b reachable by Host header through ingress; ftp-app reachable via an L4 Service (NodePort/LoadBalancer) on TCP 21.
- **Weak:** exposes all three with LoadBalancer/NodePort and never uses Ingress; or tries to put FTP behind the HTTP Ingress and can't explain why it fails.
- **Solid:** Services + Ingress for the web apps, an L4 Service for FTP.
- **Strong:** articulates that Ingress is L7/HTTP-only, names ingress-nginx TCP-services as the alternative, checks endpoints to debug.

## 2. multi-env-helm (Q4)
**Auto-pass:** `helm template` with each env file renders replicas 1/2/5 and image tags dev/staging/prod.
- **Weak:** copies the chart per env, or edits the template hardcoding values.
- **Solid:** overrides only via `values-<env>.yaml`.
- **Strong:** explains values precedence, mentions `--set`, `helm upgrade -f`, or a GitOps values-per-env layout; keeps one chart as source of truth.

## 3. debug-container-vm (Q10)
**Auto-pass:** `curl localhost:8080` returns 200.
- **Weak:** randomly recreates the container until it works, no diagnosis.
- **Solid:** reads `docker ps` PORTS, spots the 8080→8080 vs listen-on-80 mismatch, re-maps.
- **Strong:** verifies from inside the container first (`docker exec`), explains the layers (running ≠ mapped ≠ reachable).

## 4. ha-hardening (Q6) — High
**Auto-pass:** replicas ≥ 3, a PDB selecting the app, node spread (anti-affinity/topologySpread), a readinessProbe, ≥ 2 available.
- **Weak:** only bumps replicas.
- **Solid:** replicas + PDB + spread + probe all present and correct.
- **Strong:** explains PDBs cover *voluntary* disruption only, hard vs soft anti-affinity trade-offs on a small cluster, and names the cluster-level tier (multi-AZ/multi-cluster) as the next layer.

## 5. fix-crashloop
**Auto-pass:** `api` Deployment fully Ready.
- **Weak:** deletes/recreates without knowing why.
- **Solid:** uses `describe`/events, identifies ImagePullBackOff, fixes the tag.
- **Strong:** distinguishes image-pull vs crashloop vs bad-probe vs scheduling from the symptoms and says how each differs.

## 6. shared-pipeline-library (Q3)
**Auto-pass:** both builds still produce their artifacts, a shared file is sourced by both, packaging stage no longer duplicated inline.
- **Weak:** leaves duplication, or breaks one build.
- **Solid:** extracts a sourced library, parameterises by service name.
- **Strong:** relates it to Jenkins Shared Libraries / GH reusable workflows / GitLab `include`, discusses versioning the shared lib.

## 7. private-registry (Q7)
**Auto-pass:** registry answers on :5000 and `internal/app:1.0` is in the catalog.
- **Weak:** can't get push working, confuses local image list with registry contents.
- **Solid:** runs registry:2, tags, pushes, confirms via `_catalog`.
- **Strong:** connects to Nexus/Artifactory/Harbor/ECR, mentions auth, retention, and pull-through caching for apt/pypi/npm.

## 8. dockerfile-multistage
**Auto-pass:** image builds, serves `hello from app` on 8080, final image < 50 MB.
- **Weak:** can't get under the size limit, or breaks the runtime.
- **Solid:** multi-stage build, minimal final base, `CGO_ENABLED=0`.
- **Strong:** also covers layer caching/ordering, `.dockerignore`, pinned tags, non-root user.

## 9. configmap-secret-wiring
**Auto-pass:** ConfigMap `app-config` (APP_COLOR=blue) + Secret `app-secret` (API_KEY=s3cr3t) created and injected; pod env matches; sourced via valueFrom/envFrom, not hardcoded.
- **Weak:** hardcodes env values in the pod spec.
- **Solid:** proper ConfigMap + Secret + valueFrom wiring.
- **Strong:** notes Secrets are base64 not encrypted-at-rest by default, files-vs-env, external secret stores.

## 10. service-endpoints-debug
**Auto-pass:** Service `orders` has ≥ 1 endpoint and targetPort 8080.
- **Weak:** deletes/recreates the Service or the pods blindly.
- **Solid:** compares selector to pod labels, fixes the selector, confirms endpoints.
- **Strong:** checks `get endpoints` first; separates selector mismatch from targetPort mismatch from unhealthy pods.
