#!/bin/bash
set -e
systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 3

APP=/root/app
mkdir -p "$APP"

cat > "$APP/go.mod" <<'EOF'
module app

go 1.22
EOF

cat > "$APP/main.go" <<'EOF'
package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "hello from app")
	})
	http.ListenAndServe(":8080", nil)
}
EOF

# Naive single-stage Dockerfile: correct, but huge (ships the whole toolchain).
cat > "$APP/Dockerfile" <<'EOF'
FROM golang:1.22
WORKDIR /src
COPY . .
RUN go build -o /app .
EXPOSE 8080
CMD ["/app"]
EOF

# Pre-pull bases so the candidate isn't blocked on network.
docker pull golang:1.22 >/dev/null 2>&1 || true
docker pull alpine:3.20 >/dev/null 2>&1 || true

touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Build the candidate's Dockerfile, assert it runs and is < 50 MB.
fail() { echo "❌ $1"; exit 0; }
APP=/root/app
TAG=badge-multistage:grade
LIMIT=$((50*1024*1024))

[ -f "$APP/Dockerfile" ] || fail "No Dockerfile in $APP."

docker rm -f badge-grade >/dev/null 2>&1 || true
docker build -q -t "$TAG" "$APP" >/dev/null 2>&1 || fail "docker build failed. Make sure the Dockerfile still builds the app."

# Runs and serves on 8080?
docker run -d --name badge-grade -p 18080:8080 "$TAG" >/dev/null 2>&1 || fail "Container failed to start from the built image."
ok=""
for i in 1 2 3 4 5; do
  body=$(curl -s --max-time 3 http://localhost:18080/ 2>/dev/null)
  echo "$body" | grep -q "hello from app" && { ok=1; break; }
  sleep 1
done
docker rm -f badge-grade >/dev/null 2>&1 || true
[ -n "$ok" ] || fail "Image built but the app did not return 'hello from app' on port 8080. Keep the CMD/EXPOSE serving the binary."

# Size check.
size=$(docker image inspect "$TAG" --format '{{.Size}}' 2>/dev/null)
if [ -z "$size" ] || [ "$size" -ge "$LIMIT" ] 2>/dev/null; then
  human=$(( ${size:-0} / 1024 / 1024 ))
  fail "Image is ${human} MB — must be under 50 MB. Use a multi-stage build and a minimal final base."
fi

echo "✅ Image builds, serves on 8080, and is $(( size/1024/1024 )) MB (< 50 MB)."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
