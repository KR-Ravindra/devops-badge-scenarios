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
