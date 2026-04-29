#!/bin/bash
# lib-common.sh — Shared bootstrap utilities

# GitHub API helper — reuses auth headers (ADR-0104 pattern)
gh_api() {
  curl -sf \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

# Set a GitHub Actions secret using libsodium-encrypted PUT (GitHub API requirement).
# Tries gh CLI first, falls back to Python + PyNaCl.
set_github_secret() {
  local REPO="$1" NAME="$2" VALUE="$3"

  if command -v gh &>/dev/null; then
    echo -n "$VALUE" | gh secret set "$NAME" --repo "$REPO"
    return 0
  fi

  local KEY_JSON KEY_ID PUB_KEY ENCRYPTED
  KEY_JSON=$(gh_api "https://api.github.com/repos/$REPO/actions/secrets/public-key")
  KEY_ID=$(echo "$KEY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['key_id'])")
  PUB_KEY=$(echo "$KEY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])")

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

  HTTP_CODE=$(gh_api -s -o /dev/null -w "%{http_code}" -X PUT \
    "https://api.github.com/repos/$REPO/actions/secrets/$NAME" \
    -d "{\"encrypted_value\":\"$ENCRYPTED\",\"key_id\":\"$KEY_ID\"}")
  if [[ "$HTTP_CODE" != "201" && "$HTTP_CODE" != "204" ]]; then
    echo "ERROR: Failed to set secret $NAME (HTTP $HTTP_CODE)"
    exit 1
  fi
}

# Store a secret in GCP Secret Manager (hub or local project).
# Creates new secret or adds a new version if it already exists.
store_sm_secret() {
  local name="$1" value="$2" project="${3:-$SECRETS_HUB_PROJECT}"
  if gcloud secrets describe "$name" --project="$project" &>/dev/null; then
    printf '%s' "$value" | gcloud secrets versions add "$name" --project="$project" --data-file=-
  else
    printf '%s' "$value" | gcloud secrets create "$name" --project="$project" \
      --replication-policy=automatic --data-file=-
  fi
  echo "  ✅ $name"
}
