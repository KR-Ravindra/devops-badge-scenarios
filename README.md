# DevOps Badge Scenarios (KillerCoda)

Hands-on assessment scenarios for the internal DevOps badge. Candidates *solve* a
broken/empty environment instead of answering verbal questions. Each scenario
auto-grades via `verify-*.sh`.

> **Private on purpose:** the `verify-*.sh` scripts contain grading logic and
> expected answers. Keep this repo private. On KillerCoda, set each scenario's
> visibility to **Unlisted** so it's link-only and not discoverable.

## Scenarios

| Dir              | Source question | Skills tested                                   | Difficulty |
|------------------|-----------------|-------------------------------------------------|------------|
| `ingress-3-apps` | Q9              | Services, Ingress (L7/HTTP) vs L4 for non-HTTP  | Medium     |

## KillerCoda format (per scenario dir)

- `index.json` — scenario definition: intro, steps (each with a `verify` script), finish, backend image.
- `intro.md` / `step*.md` / `finish.md` — markdown shown to the candidate.
- `setup.sh` — background script that seeds the environment (runs on `host01`).
- `verify-*.sh` — grading script per step; exit `0` = pass, non-zero = fail (last line shown to candidate).

## Publishing

1. Push to GitHub (private).
2. On killercoda.com → Creator dashboard → link this repo.
3. Set each scenario to **Unlisted**.
4. Share the direct link with the candidate during a screen-shared session.

Reference patterns: `killercoda/scenario-examples` (forked at `k-r-ravindra/scenario-examples`).
