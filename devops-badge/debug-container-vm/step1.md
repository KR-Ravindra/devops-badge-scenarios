# Step 1 — Make the app reachable

A web app is deployed with Docker Compose at `/root/app/docker-compose.yml` and is
running, but this fails:

```
curl http://localhost:8080
```

**Goal:** make `curl http://localhost:8080` return the web page.

The Compose file is open in the editor — diagnose why it's unreachable and fix it.
Apply your change with:

```
cd /root/app && docker compose up -d
```

**Check your result anytime** (does not block you):

```
check
```

Click **Continue** whenever you want to move on — you can proceed even if it's not
passing yet.
