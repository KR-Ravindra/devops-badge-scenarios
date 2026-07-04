#!/bin/bash
set -e
# Ensure docker is up.
systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 3

# Ensure a docker compose command exists (plugin + standalone), download if missing.
if ! docker compose version >/dev/null 2>&1; then
  mkdir -p /root/.docker/cli-plugins
  curl -sSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
    -o /root/.docker/cli-plugins/docker-compose 2>/dev/null && chmod +x /root/.docker/cli-plugins/docker-compose || true
  cp /root/.docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null || true
fi

# App defined via Compose. Fault: host 8080 mapped to container 8080, but nginx listens on 80.
mkdir -p /root/app
cat > /root/app/docker-compose.yml <<'EOF'
services:
  web:
    image: nginx:stable
    container_name: web
    ports:
      - "8080:8080"
    restart: unless-stopped
EOF

docker rm -f web >/dev/null 2>&1 || true
( cd /root/app && docker compose up -d >/dev/null 2>&1 || docker-compose up -d >/dev/null 2>&1 || true )

# Install a self-serve grader the candidate (or interviewer) can run anytime.
cat > /usr/local/bin/check <<'EOF'
#!/bin/bash
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8080 2>/dev/null)
if [ "$code" = "200" ]; then
  echo "✅ PASS — http://localhost:8080 returns 200. The app is reachable."
else
  echo "❌ NOT YET — localhost:8080 returned '${code:-no response}'."
  echo "   The container is running, but the host port isn't reaching the app's real listen port."
fi
EOF
chmod +x /usr/local/bin/check

touch /tmp/setup-done
