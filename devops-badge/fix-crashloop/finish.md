# Done

The Deployment referenced a non-existent image tag, so pods sat in
`ImagePullBackOff`. Pointing it at a valid tag rolls it out cleanly.

**What this tests**

- Reading pod state and `describe` events instead of guessing.
- Distinguishing image-pull failures from crash loops, bad probes, or scheduling
  problems — each has a different fix.
- Strong candidates narrate the diagnosis ("status says ImagePullBackOff, events
  say manifest unknown → the tag is wrong") before applying the fix.
