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
#     [--secrets-hub-project <hub-project-id>]  (default: or-infra-templet-admin) \
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
SECRETS_HUB_PROJECT="or-infra-templet-admin"

while [[ $# -gt 0 ]]; do
  case $1 in
    --org)                ORG="$2";              shift 2 ;;
    --gcp-project)        GCP_PROJECT="$2";     shift 2 ;;
    --secrets-hub-project) SECRETS_HUB_PROJECT="$2"; shift 2 ;;
    --new-repo)           NEW_REPO="$2";        shift 2 ;;
    --enable-railway)     ENABLE_RAILWAY="$2";  shift 2 ;;
    --enable-cloudflare)  ENABLE_CLOUDFLARE="$2"; shift 2 ;;
    --enable-n8n)         ENABLE_N8N="$2";      shift 2 ;;
    --yes|-y)             AUTO_APPROVE="true";  shift ;;
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

# Source shared bootstrap utilities
source "$SCRIPT_DIR/lib-common.sh"

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

# Populate terraform.tfvars from variables (single pass, anchored patterns)
sed -i \
  -e "s|^github_org\s*=.*|github_org = \"$ORG\"|" \
  -e "s|^gcp_project_id\s*=.*|gcp_project_id = \"$GCP_PROJECT\"|" \
  -e "s|^secrets_hub_project_id\s*=.*|secrets_hub_project_id = \"$SECRETS_HUB_PROJECT\"|" \
  -e "s|^enable_railway\s*=.*|enable_railway = $ENABLE_RAILWAY|" \
  -e "s|^enable_cloudflare\s*=.*|enable_cloudflare = $ENABLE_CLOUDFLARE|" \
  -e "s|^enable_n8n\s*=.*|enable_n8n = $ENABLE_N8N|" \
  terraform/terraform.tfvars

# Read GitHub App ID from secrets hub (must come after gcloud is auth'd)
APP_ID=$(gcloud secrets versions access latest \
  --secret="github-app-id" \
  --project="$SECRETS_HUB_PROJECT")
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

  # Set GitHub secrets (key-value pairs)
  set_github_secret "$ORG/$NEW_REPO" "GCP_WORKLOAD_IDENTITY_PROVIDER" "$WIF_PROVIDER"
  set_github_secret "$ORG/$NEW_REPO" "GCP_SERVICE_ACCOUNT_EMAIL"      "$SA_EMAIL"
  set_github_secret "$ORG/$NEW_REPO" "GCP_SECRETS_HUB_PROJECT"         "$SECRETS_HUB_PROJECT"
  set_github_secret "$ORG/$NEW_REPO" "GH_APP_ID"                      "$APP_ID"
  echo "  ✓ Secrets set (WIF, hub project, app ID)"

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
