# Done

A multi-stage build compiles the binary in the full `golang` image, then copies
only that binary into a tiny base — the toolchain never ships. ~800 MB → well
under 50 MB, same behaviour.

**What this tests**

- Multi-stage builds and why the final stage should be minimal.
- Knowing `CGO_ENABLED=0` produces a static binary that runs on alpine/scratch.
- Strong candidates also mention layer ordering/caching, `.dockerignore`, pinning
  base tags, and running as non-root — image hygiene beyond just size.
