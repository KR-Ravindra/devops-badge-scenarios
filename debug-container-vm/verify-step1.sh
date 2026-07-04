#!/bin/bash
# Pass when the app answers on host port 8080.
fail() { echo "❌ $1"; exit 1; }

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8080 2>/dev/null)
if [ "$code" = "200" ]; then
  echo "✅ http://localhost:8080 returns 200 — the app is reachable."
  exit 0
fi

# Give a targeted nudge based on what's wrong.
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^web$'; then
  fail "No running 'web' container. Start a container that serves the app and publishes host port 8080."
fi
fail "Container is running but localhost:8080 did not return 200 (got '${code:-no response}'). Check the port mapping — is host 8080 mapped to the port the app actually listens on?"
