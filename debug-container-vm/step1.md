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

<details>
<summary>Hint</summary>

nginx listens on port **80** inside the container, but the container was published
as `-p 8080:8080`. Re-run it mapping host 8080 to container 80:

```
docker rm -f web
docker run -d --name web -p 8080:80 nginx
```
</details>
