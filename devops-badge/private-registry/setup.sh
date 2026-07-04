#!/bin/bash
set -e
systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 3
# Pre-pull a base image and the registry image so the candidate isn't blocked on network.
docker pull alpine:3.20 >/dev/null 2>&1 || docker pull alpine >/dev/null 2>&1 || true
docker pull registry:2 >/dev/null 2>&1 || true
touch /tmp/setup-done

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/_badge_check_1 <<'BADGE_CHECK_EOF_1'
#!/bin/bash
# Pass when a registry is up on :5000 and holds internal/app.
fail() { echo "❌ $1"; exit 0; }

# 1) Registry API responds.
curl -sf --max-time 5 http://localhost:5000/v2/ >/dev/null 2>&1 \
  || fail "No registry responding at http://localhost:5000/v2/. Run 'registry:2' published on port 5000."

# 2) Catalog contains internal/app.
cat=$(curl -s --max-time 5 http://localhost:5000/v2/_catalog 2>/dev/null)
echo "$cat" | grep -q "internal/app" \
  || fail "Registry is up but internal/app is not in the catalog. Tag and push localhost:5000/internal/app:1.0. (catalog: ${cat:-empty})"

# 3) The 1.0 tag exists.
tags=$(curl -s --max-time 5 http://localhost:5000/v2/internal/app/tags/list 2>/dev/null)
echo "$tags" | grep -q '"1.0"' \
  || fail "internal/app exists but tag 1.0 is missing. Push localhost:5000/internal/app:1.0. (tags: ${tags:-none})"

echo "✅ Private registry is serving localhost:5000/internal/app:1.0."
exit 0

BADGE_CHECK_EOF_1
chmod +x /usr/local/bin/_badge_check_1
cat > /usr/local/bin/check <<'BADGE_CHECK_MAIN_EOF'
#!/bin/bash
/usr/local/bin/_badge_check_1
BADGE_CHECK_MAIN_EOF
chmod +x /usr/local/bin/check
