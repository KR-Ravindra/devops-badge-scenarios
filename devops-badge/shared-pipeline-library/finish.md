# Done

The install/test/package stages now live in one shared library that both service
builds call with the service name as a parameter. Adding a third service is a
two-line script; fixing a stage is a one-place change.

**What this tests**

- DRY applied to CI/CD, not just app code.
- Parameterising shared logic (service name as an argument) rather than branching.
- Strong candidates relate this to real shared-pipeline features they've used —
  Jenkins Shared Libraries, GitHub Actions reusable/composite workflows, GitLab CI
  `include`/`extends` — and explain versioning of the shared library.
