# Done

You now have a private registry that internal images are published to and pulled
from — one central source of truth instead of everyone hitting the public internet.

**What this tests**

- Understanding of artifact/registry management: tag → push → catalog → pull.
- The registry as a shared, centralized dependency store.
- Strong candidates connect this to production tooling — Nexus, Artifactory, Harbor,
  ECR — and mention auth, retention/cleanup policies, and pull-through caching for
  upstream dependencies (apt/pypi/npm), which is the real-world version of this.
