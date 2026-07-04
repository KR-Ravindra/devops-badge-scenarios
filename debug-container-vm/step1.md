# Step 1 — Make the app reachable

The goal: `curl http://localhost:8080` returns the nginx welcome page.

Work through it methodically:

```
docker ps                 # is it running? what ports are mapped?
docker logs web           # is the app healthy inside?
docker exec web sh -c 'command -v curl && curl -sI localhost:80 || wget -qO- localhost:80 | head'
```

> Pay attention to the **PORTS** column in `docker ps` versus the port the app
> actually listens on inside the container.

Fix it, then click **Check**.