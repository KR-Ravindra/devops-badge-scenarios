# Containerized App Unreachable

A colleague deployed a web app as a Docker container on this VM. The container is
"running" but nobody can reach the site:

```
curl http://localhost:8080
```

...fails or times out.

Your job: **make `curl http://localhost:8080` return the web page.** Diagnose it
the way you would on a real EC2 box — check the container, its port mapping, what
the app inside actually listens on, and the host firewall.

Docker is installed and the container is already created. Click **START**.
