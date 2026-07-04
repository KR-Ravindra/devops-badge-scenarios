#!/bin/bash
set -e
# Ensure docker is up.
systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 3

docker rm -f web >/dev/null 2>&1 || true

# Fault: host port 8080 is mapped to container port 8080, but nginx listens on 80.
# The port mapping is wrong, so curl localhost:8080 reaches nothing.
docker run -d --name web -p 8080:8080 nginx:stable >/dev/null 2>&1 || \
  docker run -d --name web -p 8080:8080 nginx >/dev/null 2>&1 || true

touch /tmp/setup-done
