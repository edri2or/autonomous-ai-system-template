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

while [[ $# -gt 0 ]]; do
  case $1 in
    --org)              ORG="$2";              shift 2 ;;
    --gcp-project)      GCP_PROJECT="$2";      shift 2 ;;
    --new-repo)         NEW_REPO="$2";         shift 2 ;;
    --enable-railway)   ENABLE_RAILWAY="$2";   shift 2 ;;
    --enable-cloudflare) ENABLE_CLOUDFLARE="$2"; shift 2 ;;
    --enable-n8n)       ENABLE_N8N="$2";       shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$ORG" || -z "$GCP_PROJECT" || -z "$NEW_REPO" ]]; then
  echo "Usage: $0 --org ORG --gcp-project PROJECT --new-repo REPO [options]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# --------------------------------------------------------------------------
# Phase 1: Verify prerequisites
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 1: Verify Prerequisites ==="
bash "$ROOT_DIR/scripts/verify-gate-001.sh" "$GCP_PROJECT" || exit 1
bash "$ROOT_DIR/scripts/verify-gate-002.sh" "$GCP_PROJECT"  || exit 1
bash "$ROOT_DIR/scripts/verify-gate-003.sh" "$GCP_PROJECT"  || exit 1
echo "✓ All prerequisites verified"

# --------------------------------------------------------------------------
# Phase 2: Create GitHub repository from template
# --------------------------------------------------------------------------
echo ""
echo "=== Phase 2: Create GitHub Repository ==="

# Use GitHub API with Bearer token (ADR-0104 pattern)
GH_TOKEN="${GH_TOKEN:-}"
if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: GH_TOKEN environment variable must be set"
  exit 1
fi

HTTP_RESP=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GH_TOKEN" \
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

WORK_DIR="/tmp/bootstrap-$$"
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

sed -i "s|github_org.*=.*|github_org = \"$ORG\"|g"                   terraform/terraform.tfvars
sed -i "s|gcp_project_id.*=.*|gcp_project_id = \"$GCP_PROJECT\"|g"   terraform/terraform.tfvars
sed -i "s|enable_railway.*=.*|enable_railway = $ENABLE_RAILWAY|g"     terraform/terraform.tfvars
sed -i "s|enable_cloudflare.*=.*|enable_cloudflare = $ENABLE_CLOUDFLARE|g" terraform/terraform.tfvars
sed -i "s|enable_n8n.*=.*|enable_n8n = $ENABLE_N8N|g"               terraform/terraform.tfvars

# Read GitHub App ID from GCP Secret Manager
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
read -r -p "Apply Terraform plan? (yes/no) " REPLY
echo ""

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

  for SECRET_NAME in "GCP_WORKLOAD_IDENTITY_PROVIDER:$WIF_PROVIDER" "GCP_SERVICE_ACCOUNT_EMAIL:$SA_EMAIL" "GITHUB_APP_ID:$APP_ID"; do
    NAME="${SECRET_NAME%%:*}"
    VALUE="${SECRET_NAME##*:}"
    curl -s -X PUT \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/repos/$ORG/$NEW_REPO/actions/secrets/$NAME" \
      -d "{\"encrypted_value\":\"$(echo -n "$VALUE" | base64)\"}" > /dev/null
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

  curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_TOKEN" \
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
