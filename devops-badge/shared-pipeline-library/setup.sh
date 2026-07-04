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

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Grade: both builds still work, a shared lib is sourced, and duplication is gone.
fail() { echo "❌ $1"; exit 0; }
CI=/root/ci
A="$CI/build-service-a.sh"; B="$CI/build-service-b.sh"

[ -f "$A" ] && [ -f "$B" ] || fail "Expected build-service-a.sh and build-service-b.sh in $CI."

# 1) Both builds run and produce artifacts (clean first so we test a real run).
rm -rf "$CI/out"
for s in a b; do
  bash "$CI/build-service-$s.sh" >/dev/null 2>&1 || fail "build-service-$s.sh exited non-zero — the refactor broke the build."
done
for s in service-a service-b; do
  for kind in deps tests artifact; do
    [ -s "$CI/out/$s.$kind" ] || fail "Missing $CI/out/$s.$kind — the $kind stage no longer runs for $s."
  done
done
grep -q "service-a v1.0" "$CI/out/service-a.artifact" || fail "service-a artifact content is wrong after refactor."
grep -q "service-b v1.0" "$CI/out/service-b.artifact" || fail "service-b artifact content is wrong after refactor."

# 2) A shared file is pulled in by BOTH scripts.
shared_ok=1
for f in "$A" "$B"; do
  grep -Eq '^\s*(source|\.)\s+' "$f" || shared_ok=0
done
[ "$shared_ok" = "1" ] || fail "Neither/only one build script sources a shared file. Extract the common stages into one library both scripts use."

# 3) Duplication gone: the packaging stage logic should no longer be inline in BOTH scripts.
dupe=0
for f in "$A" "$B"; do
  grep -q "packaging artifact" "$f" && dupe=$((dupe+1))
done
[ "$dupe" -ge 2 ] && fail "The packaging stage is still copy-pasted inline in both scripts. Move it into the shared library."

echo "✅ Both builds pass, a shared library is sourced by both, and the duplicated stages were extracted."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
