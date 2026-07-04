# Done

The container was published as `-p 8080:8080`, but nginx listens on port **80**.
Mapping host `8080` → container `80` fixes it.

**What this tests**

- Reading `docker ps` PORTS and reconciling it with the app's real listen port.
- A layered mental model: container running ≠ app reachable ≠ port mapped correctly.
- Strong candidates verify from inside the container (`docker exec`) before touching
  the host, and explain each layer they ruled out.
