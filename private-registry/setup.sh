#!/bin/bash
set -e
systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 3
# Pre-pull a base image and the registry image so the candidate isn't blocked on network.
docker pull alpine:3.20 >/dev/null 2>&1 || docker pull alpine >/dev/null 2>&1 || true
docker pull registry:2 >/dev/null 2>&1 || true
touch /tmp/setup-done
