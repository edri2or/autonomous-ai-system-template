#!/bin/bash
# lib-common.sh — Shared bootstrap utilities

# GitHub API helper — reuses auth headers (ADR-0104 pattern)
# Requires: GH_TOKEN environment variable
# Example: gh_api -X GET "https://api.github.com/..."
gh_api() {
  curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_TOKEN" \
    "$@"
}

# Set a GitHub Actions secret using libsodium-encrypted PUT (GitHub API requirement).
# Tries gh CLI first, falls back to Python + PyNaCl.
# Requires: GH_TOKEN environment variable
set_github_secret() {
  local REPO="$1" NAME="$2" VALUE="$3"

  [[ $# -ne 3 ]] && { echo "ERROR: set_github_secret requires 3 arguments: REPO NAME VALUE" >&2; return 1; }

  if command -v gh &>/dev/null; then
    echo -n "$VALUE" | gh secret set "$NAME" --repo "$REPO"
    return 0
  fi

  local KEY_ID PUB_KEY ENCRYPTED
  # Parse both key_id and key in ONE Python process (fixes redundant subprocess creation)
  read -r KEY_ID PUB_KEY < <(gh_api -X GET \
    "https://api.github.com/repos/$REPO/actions/secrets/public-key" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['key_id'], d['key'])")

  ENCRYPTED=$(python3 - "$VALUE" "$PUB_KEY" <<'PYEOF'
import sys, base64
value, pub_key = sys.argv[1], sys.argv[2]
try:
    from nacl.public import PublicKey, SealedBox
    box = SealedBox(PublicKey(base64.b64decode(pub_key)))
    print(base64.b64encode(box.encrypt(value.encode())).decode())
except ImportError:
    print("PyNaCl not installed", file=sys.stderr)
    sys.exit(2)
PYEOF
  ) || {
    echo "ERROR: cannot set secrets automatically — install gh CLI or PyNaCl:"
    echo "  brew install gh   (then: gh auth login)"
    echo "  pip install PyNaCl"
    exit 1
  }

  # Use Python json module for safe JSON construction (fixes shell injection vulnerability)
  local JSON_PAYLOAD
  JSON_PAYLOAD=$(python3 -c "import json, sys; print(json.dumps({'encrypted_value': '$ENCRYPTED', 'key_id': '$KEY_ID'}))")

  local HTTP_CODE
  HTTP_CODE=$(gh_api -X PUT -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    "https://api.github.com/repos/$REPO/actions/secrets/$NAME")

  if [[ "$HTTP_CODE" != "201" && "$HTTP_CODE" != "204" ]]; then
    echo "ERROR: Failed to set secret $NAME (HTTP $HTTP_CODE)"
    return 1
  fi
}
