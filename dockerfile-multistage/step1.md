# Step 1 — Small and still working

Edit `/root/app/Dockerfile` so the built image is **< 50 MB** and the app still
serves `hello from app` on port 8080.

Test it yourself:

```
cd /root/app
docker build -t app:slim .
docker images app:slim              # check the SIZE column
docker run -d -p 8080:8080 --name t app:slim && sleep 1 && curl localhost:8080
```

Then click **Check** (the grader builds your Dockerfile itself).