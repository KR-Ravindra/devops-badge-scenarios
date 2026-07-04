#!/bin/bash
# Pass when a registry is up on :5000 and holds internal/app.
fail() { echo "❌ $1"; exit 1; }

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
