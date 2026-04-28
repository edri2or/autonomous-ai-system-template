#!/bin/bash
# bootstrap-new-project.sh
#
# Creates a new autonomous AI project from the template.
# Run AFTER completing all manual gates (see docs/gates/manual-gates.md).
#
# Usage:
#   ./bootstrap/bootstrap-new-project.sh \
#     --org        <github-org>         \
#     --gcp-project <gcp-project-id>    \
#     --new-repo   <new-repo-name>      \
#     [--enable-railway    true|false]  \
#     [--enable-cloudflare true|false]  \
#     [--enable-n8n        true|false]

set -euo pipefail

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
ORG=""
GCP_PROJECT=""
NEW_REPO=""
ENABLE_RAILWAY="false"
ENABLE_CLOUDFLARE="false"
ENABLE_N8N="false"
AUTO_APPROVE="${AUTO_APPROVE:-false}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --org)              ORG="$2";              shift 2 ;;
    --gcp-project)      GCP_PROJECT="$2";      shift 2 ;;
    --new-repo)         NEW_REPO="$2";         shift 2 ;;
    --enable-railway)   ENABLE_RAILWAY="$2";   shift 2 ;;
    --enable-cloudflare) ENABLE_CLOUDFLARE="$2"; shift 2 ;;
    --enable-n8n)       ENABLE_N8N="$2";       shift 2 ;;
    --yes|-y)           AUTO_APPROVE="true";   shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$ORG" || -z "$GCP_PROJECT" || -z "$NEW_REPO" ]]; then
  echo "Usage: $0 --org ORG --gcp-project PROJECT --new-repo REPO [options]"
  echo "  --yes / -y    Auto-approve Terraform apply (required for non-interactive use)"
  exit 1
fi

GH_TOKEN="${GH_TOKEN:-}"
if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: GH_TOKEN environment variable must be set"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="/tmp/bootstrap-$$"

# Clean up working directory on exit
trap 'rm -rf "$WORK_DIR"' EXIT

# GitHub API helper — reuses auth headers (ADR-0104 pattern)
gh_api() {
  curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_TOKEN" \
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

# --------------------------------------------------------------------------
# Phase 1: Verify prerequisites
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 1: Verify Prerequisites ==="
bash "$ROOT_DIR/scripts/verify-gate-001.sh" "$GCP_PROJECT" || exit 1
bash "$ROOT_DIR/scripts/verify-gate-002.sh" "$GCP_PROJECT" || echo "WARN: GATE-002 — WIF not pre-created; Terraform will create it"
bash "$ROOT_DIR/scripts/verify-gate-003.sh" "$GCP_PROJECT" || echo "WARN: GATE-003 — SA not pre-created; Terraform will create it"
echo "✓ All prerequisites verified"

# --------------------------------------------------------------------------
# Phase 2: Create GitHub repository from template
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 2: Create GitHub Repository ==="

HTTP_RESP=$(gh_api -w "\n%{http_code}" -X POST \
  "https://api.github.com/repos/${ORG}/autonomous-ai-system-template/generate" \
  -d "{\"owner\":\"$ORG\",\"name\":\"$NEW_REPO\",\"private\":true,\"description\":\"Autonomous AI project created from template\"}")

HTTP_CODE=$(echo "$HTTP_RESP" | tail -1)
BODY=$(echo "$HTTP_RESP" | head -1)

if [[ "$HTTP_CODE" != "201" ]]; then
  echo "ERROR: Failed to create repository (HTTP $HTTP_CODE)"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  exit 1
fi

echo "✓ GitHub repository created: $ORG/$NEW_REPO"

# --------------------------------------------------------------------------
# Phase 3: Clone new repository
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 3: Clone Repository ==="

mkdir -p "$WORK_DIR"
git clone "https://x-access-token:${GH_TOKEN}@github.com/$ORG/$NEW_REPO.git" "$WORK_DIR/$NEW_REPO"
cd "$WORK_DIR/$NEW_REPO"

echo "✓ Repository cloned to $WORK_DIR/$NEW_REPO"

# --------------------------------------------------------------------------
# Phase 4: Configure Terraform
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 4: Configure Terraform ==="

cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Combine first 5 substitutions into a single sed pass
sed -i \
  -e "s|github_org.*=.*|github_org = \"$ORG\"|g" \
  -e "s|gcp_project_id.*=.*|gcp_project_id = \"$GCP_PROJECT\"|g" \
  -e "s|enable_railway.*=.*|enable_railway = $ENABLE_RAILWAY|g" \
  -e "s|enable_cloudflare.*=.*|enable_cloudflare = $ENABLE_CLOUDFLARE|g" \
  -e "s|enable_n8n.*=.*|enable_n8n = $ENABLE_N8N|g" \
  terraform/terraform.tfvars

# Read GitHub App ID from GCP Secret Manager (must come after gcloud is auth'd)
APP_ID=$(gcloud secrets versions access latest \
  --secret="github-app-id" \
  --project="$GCP_PROJECT")
sed -i "s|github_app_id.*=.*|github_app_id = \"$APP_ID\"|g" terraform/terraform.tfvars

echo "✓ terraform.tfvars populated"

# --------------------------------------------------------------------------
# Phase 5: Terraform init + plan
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 5: Terraform Plan ==="

cd terraform/
terraform init -upgrade -var-file="terraform.tfvars"
terraform plan -var-file="terraform.tfvars" -out="tfplan"

echo ""
echo "✓ Terraform plan complete (review output above)"

echo ""
if [[ "$AUTO_APPROVE" == "true" ]]; then
  REPLY="yes"
else
  read -r -p "Apply Terraform plan? (yes/no) " REPLY
  echo ""
fi

if [[ "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then

  # --------------------------------------------------------------------------
  # Phase 6: Terraform apply
  # --------------------------------------------------------------------------
  echo "=== Phase 6: Terraform Apply ==="
  terraform apply tfplan
  echo "✓ Terraform apply complete"

  WIF_PROVIDER=$(terraform output -raw wif_provider_resource_name)
  SA_EMAIL=$(terraform output -raw service_account_email)

  # --------------------------------------------------------------------------
  # Phase 7: Create GitHub Secrets
  # --------------------------------------------------------------------------
  echo ""
  echo "=== Phase 7: Create GitHub Secrets ==="
  cd ..

  for SECRET_NAME in "GCP_WORKLOAD_IDENTITY_PROVIDER:$WIF_PROVIDER" "GCP_SERVICE_ACCOUNT_EMAIL:$SA_EMAIL" "GH_APP_ID:$APP_ID"; do
    NAME="${SECRET_NAME%%:*}"
    VALUE="${SECRET_NAME##*:}"
    set_github_secret "$ORG/$NEW_REPO" "$NAME" "$VALUE"
    echo "  ✓ Secret $NAME set"
  done

  # --------------------------------------------------------------------------
  # Phase 8: Commit bootstrap state
  # --------------------------------------------------------------------------
  echo ""
  echo "=== Phase 8: Commit Bootstrap State ==="

  git config user.name "bootstrap"
  git config user.email "bootstrap@autonomous.local"
  git add terraform/terraform.tfvars
  git add -f terraform/terraform.tfstate 2>/dev/null || true
  git commit -m "Bootstrap: initial Terraform state for $NEW_REPO" || echo "Nothing to commit"
  git push origin main

  echo "✓ Bootstrap state committed"

  # --------------------------------------------------------------------------
  # Phase 9: Trigger autonomous setup workflow
  # --------------------------------------------------------------------------
  echo ""
  echo "=== Phase 9: Trigger Autonomous Control Plane ==="

  gh_api -X POST \
    "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/autonomous-control-plane.yml/dispatches" \
    -d '{"ref":"main","inputs":{"skip_provider_validation":"false"}}' \
    && echo "✓ Autonomous control plane triggered" \
    || echo "WARN: Could not trigger workflow (may need manual trigger)"

  echo ""
  echo "================================================================"
  echo "Bootstrap complete!"
  echo "  Repository: https://github.com/$ORG/$NEW_REPO"
  echo "  Actions:    https://github.com/$ORG/$NEW_REPO/actions"
  echo "================================================================"

else
  echo "Terraform apply cancelled."
  echo "To resume:"
  echo "  cd $WORK_DIR/$NEW_REPO/terraform"
  echo "  terraform apply tfplan"
fi
