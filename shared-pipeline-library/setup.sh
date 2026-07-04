#!/bin/bash
set -e
CI=/root/ci
mkdir -p "$CI"

# Two near-identical build scripts. Only the SERVICE name differs; the install,
# test and package stages are copy-pasted.
cat > "$CI/build-service-a.sh" <<'EOF'
#!/bin/bash
set -e
SERVICE=service-a
echo "[$SERVICE] installing dependencies..."
mkdir -p /root/ci/out
echo "deps installed for $SERVICE" > /root/ci/out/$SERVICE.deps
echo "[$SERVICE] running tests..."
echo "tests passed for $SERVICE" > /root/ci/out/$SERVICE.tests
echo "[$SERVICE] packaging artifact..."
echo "artifact: $SERVICE v1.0" > /root/ci/out/$SERVICE.artifact
echo "[$SERVICE] build complete"
EOF

cat > "$CI/build-service-b.sh" <<'EOF'
#!/bin/bash
set -e
SERVICE=service-b
echo "[$SERVICE] installing dependencies..."
mkdir -p /root/ci/out
echo "deps installed for $SERVICE" > /root/ci/out/$SERVICE.deps
echo "[$SERVICE] running tests..."
echo "tests passed for $SERVICE" > /root/ci/out/$SERVICE.tests
echo "[$SERVICE] packaging artifact..."
echo "artifact: $SERVICE v1.0" > /root/ci/out/$SERVICE.artifact
echo "[$SERVICE] build complete"
EOF

chmod +x "$CI"/build-service-*.sh
touch /tmp/setup-done
