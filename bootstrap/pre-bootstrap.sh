#!/bin/bash
# bootstrap/pre-bootstrap.sh
#
# Cloud Shell one-command bootstrap for a new autonomous AI project.
# No SA key required — uses GCP Application Default Credentials (Cloud Shell is pre-authenticated).
#
# GCP project and GitHub org are auto-detected from the environment.
# Only the new project name is required.
#
# User actions required (everything else is automated):
#   1. export GH_TOKEN="ghp_..."   # Classic PAT: repo, workflow, admin:org
#   2. Run this script from GCP Cloud Shell
#   3. Open the URL shown and click "Create GitHub App" on GitHub
#   4. Click "Install App" button
#   5. Confirm Terraform apply when prompted (or pass --yes to skip)
#
# Usage:
#   export GH_TOKEN="ghp_..."
#   bash bootstrap/pre-bootstrap.sh --new-repo MY_PROJECT_NAME
#
# Optional overrides (auto-detected if omitted):
#   --gcp-project         GCP_PROJECT_ID        (default: current gcloud project)
#   --org                 GITHUB_ORG            (default: owner of this template repo)
#   --secrets-hub-project HUB_PROJECT_ID        (default: or-infra-templet-admin)
#   --enable-railway      true|false
#   --enable-cloudflare   true|false
#   --enable-n8n          true|false
#   --railway-token       RAILWAY_API_TOKEN     (required if --enable-railway true)
#   --cf-token            CF_API_TOKEN          (required if --enable-cloudflare true)
#   --cf-zone-id          CF_ZONE_ID            (required if --enable-cloudflare true)
#   --project-domain      my.domain.com         (required if --enable-n8n true, e.g. myproject.or-infra.com)
#   --n8n-subdomain       n8n                   (default: n8n)
#   --n8n-admin-email     admin@my.domain       (required if --enable-n8n true)
#   --yes                                       (skip Terraform confirm)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load shared bootstrap utilities (gh_api, set_github_secret, store_sm_secret)
source "$SCRIPT_DIR/lib-common.sh"

ORG=""; GCP_PROJECT=""; NEW_REPO=""
ENABLE_RAILWAY="false"; ENABLE_CLOUDFLARE="false"; ENABLE_N8N="false"
RAILWAY_TOKEN=""; CF_TOKEN=""; CF_ZONE_ID=""
PROJECT_DOMAIN=""; N8N_SUBDOMAIN="n8n"; N8N_ADMIN_EMAIL=""
AUTO_APPROVE="${AUTO_APPROVE:-false}"
SECRETS_HUB_PROJECT="or-infra-templet-admin"

while [[ $# -gt 0 ]]; do
  case $1 in
    --org)                ORG="$2";               shift 2 ;;
    --gcp-project)        GCP_PROJECT="$2";      shift 2 ;;
    --secrets-hub-project) SECRETS_HUB_PROJECT="$2"; shift 2 ;;
    --new-repo)           NEW_REPO="$2";         shift 2 ;;
    --enable-railway)     ENABLE_RAILWAY="$2";   shift 2 ;;
    --enable-cloudflare)  ENABLE_CLOUDFLARE="$2"; shift 2 ;;
    --enable-n8n)         ENABLE_N8N="$2";       shift 2 ;;
    --railway-token)      RAILWAY_TOKEN="$2";    shift 2 ;;
    --cf-token)           CF_TOKEN="$2";         shift 2 ;;
    --cf-zone-id)         CF_ZONE_ID="$2";       shift 2 ;;
    --project-domain)     PROJECT_DOMAIN="$2";   shift 2 ;;
    --n8n-subdomain)      N8N_SUBDOMAIN="$2";    shift 2 ;;
    --n8n-admin-email)    N8N_ADMIN_EMAIL="$2";  shift 2 ;;
    --yes|-y)             AUTO_APPROVE="true";   shift   ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

GH_TOKEN="${GH_TOKEN:-}"
[[ -z "$GH_TOKEN" ]] && { echo "ERROR: GH_TOKEN is not set"; exit 1; }

# Validate Railway/Cloudflare/N8N args if enabled
if [[ "$ENABLE_RAILWAY" == "true" ]] && [[ -z "$RAILWAY_TOKEN" ]]; then
  echo "ERROR: --railway-token is required when --enable-railway true"
  echo "  Get your Railway API token: https://railway.com/account/tokens"
  exit 1
fi
if [[ "$ENABLE_CLOUDFLARE" == "true" ]] && { [[ -z "$CF_TOKEN" ]] || [[ -z "$CF_ZONE_ID" ]]; }; then
  echo "ERROR: --cf-token and --cf-zone-id are required when --enable-cloudflare true"
  exit 1
fi
if [[ "$ENABLE_N8N" == "true" ]] && { [[ -z "$PROJECT_DOMAIN" ]] || [[ -z "$N8N_ADMIN_EMAIL" ]]; }; then
  echo "ERROR: --project-domain and --n8n-admin-email are required when --enable-n8n true"
  echo "  Example: --project-domain myproject.or-infra.com --n8n-admin-email admin@myproject.or-infra.com"
  exit 1
fi

# Cloud Shell pre-sets the active project — skip prompting the user
if [[ -z "$GCP_PROJECT" ]]; then
  GCP_PROJECT=$(gcloud config get-value project 2>/dev/null)
  [[ -z "$GCP_PROJECT" ]] && {
    echo "ERROR: Could not detect GCP project. Run: gcloud config set project YOUR_PROJECT"
    exit 1
  }
fi

# The org is the owner of the repo this script ships in — no network call needed
if [[ -z "$ORG" ]]; then
  _remote=$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null)
  _remote="${_remote##*github.com[:/]}"
  ORG="${_remote%%/*}"
  [[ -z "$ORG" || "$ORG" == *"http"* ]] && {
    echo "ERROR: Could not detect GitHub org. Pass --org YOUR_ORG explicitly."
    exit 1
  }
fi

[[ -z "$NEW_REPO" ]] && {
  echo "Usage: $0 --new-repo PROJECT_NAME [options]"
  echo ""
  echo "Required env: GH_TOKEN (Classic PAT with scopes: repo, workflow, admin:org)"
  echo ""
  echo "Auto-detected from environment:"
  echo "  --gcp-project: from 'gcloud config get-value project'"
  echo "  --org:         from this repo's git remote URL"
  exit 1
}

TEMPLATE_REPO="edri2or/autonomous-ai-system-template"
SM_APP_KEY="github-app-private-key"
SM_APP_ID="github-app-id"

PEM_TMPFILE=$(mktemp)
WORK_DIR=$(mktemp -d)
cleanup() {
  shred -uz "$PEM_TMPFILE" 2>/dev/null || rm -f "$PEM_TMPFILE"
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Install PyNaCl once at startup (used by set_github_secret when gh CLI is unavailable)
if ! command -v gh &>/dev/null; then
  python3 -c "from nacl import encoding, public" 2>/dev/null \
    || python3 -m pip install --quiet PyNaCl
fi

echo "╔══════════════════════════════════════════════════════════╗"
echo "║        Autonomous AI System — Bootstrap                  ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf  "║  Org:         %-42s ║\n" "$ORG"
printf  "║  New repo:    %-42s ║\n" "$NEW_REPO"
printf  "║  GCP project: %-42s ║\n" "$GCP_PROJECT"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ══════════════════════════════════════════════════════════════
#  PHASE 1 — GitHub App (create once via manifest flow)
# ══════════════════════════════════════════════════════════════
echo "── PHASE 1: GitHub App ──────────────────────────────────────"

# Check both secrets exist with single gcloud call
if gcloud secrets describe "$SM_APP_ID" --project="$SECRETS_HUB_PROJECT" &>/dev/null && \
   gcloud secrets describe "$SM_APP_KEY" --project="$SECRETS_HUB_PROJECT" &>/dev/null; then
  echo "✅ GitHub App credentials found in secrets hub ($SECRETS_HUB_PROJECT)"
  APP_ID=$(gcloud secrets versions access latest \
    --secret="$SM_APP_ID" --project="$SECRETS_HUB_PROJECT")
else
  # Check if running in Cloud Shell
  if [[ -z "${WEB_HOST:-}" ]]; then
    echo "ERROR: WEB_HOST environment variable not set"
    echo "This script must run in GCP Cloud Shell (shell.cloud.google.com)"
    exit 1
  fi

  REDIRECT_HOST="https://8080-${WEB_HOST}"

  # Generate manifest with Cloud Shell redirect URL
  MANIFEST_ENC=$(ORG="$ORG" REDIR_HOST="$REDIRECT_HOST" python3 - <<'PYEOF'
import os, json, urllib.parse
org = os.environ["ORG"]
redir = os.environ["REDIR_HOST"]
m = {
  "name": f"{org}-agent",
  "url":  f"https://github.com/{org}",
  "hook_attributes": {"url": "https://placeholder.example.com", "active": False},
  "redirect_url": f"{redir}/callback",
  "public": False,
  "default_permissions": {
    "contents": "write", "issues": "write", "pull_requests": "write",
    "actions":  "write", "secrets": "write", "workflows":    "write",
    "metadata": "read"
  },
  "default_events": ["push", "pull_request"]
}
print(urllib.parse.quote(json.dumps(m, separators=(",", ":"))))
PYEOF
)

  STATE=$(python3 -c "import secrets; print(secrets.token_hex(16))")
  APP_URL="https://github.com/organizations/${ORG}/settings/apps/new?state=${STATE}&manifest=${MANIFEST_ENC}"

  echo ""
  echo "  ACTION REQUIRED — two clicks on GitHub:"
  echo ""
  echo "  1. Open this URL:"
  echo ""
  echo "    $APP_URL"
  echo ""
  echo "  2. Click 'Create GitHub App' button"
  echo ""
  echo "  3. Click 'Install App' button"
  echo ""
  echo "  Starting HTTP server to receive callback..."

  # Start Python HTTP server
  python3 << 'HTTPEOF' &
import http.server
import urllib.parse
import sys
import os
from pathlib import Path

class ManifestCallbackHandler(http.server.BaseHTTPRequestHandler):
    code_file = os.environ.get("CODE_FILE", "")
    
    def do_GET(self):
        if self.path.startswith("/callback?"):
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            codes = qs.get("code", [])
            if codes:
                with open(self.code_file, "w") as f:
                    f.write(codes[0])
                self.send_response(200)
                self.send_header("Content-type", "text/html")
                self.end_headers()
                self.wfile.write(b"""
<html><body>
<h1>GitHub App Created!</h1>
<p>Your app credentials have been captured.</p>
<p>You can close this window and return to Cloud Shell.</p>
</body></html>
""")
                sys.exit(0)
        self.send_response(404)
        self.end_headers()
    
    def log_message(self, format, *args):
        pass

CODE_FILE="$WORK_DIR/app_code.txt" \
python3 -m http.server 8080 -b 127.0.0.1 2>/dev/null
HTTPEOF

  HTTP_PID=$!
  sleep 1

  echo "  Waiting for redirect callback..."

  # Poll for code file (max 120 seconds = 24 * 5s)
  WAIT=0
  while [[ ! -f "$WORK_DIR/app_code.txt" ]] && [[ $WAIT -lt 24 ]]; do
    sleep 5
    WAIT=$((WAIT + 1))
  done

  kill $HTTP_PID 2>/dev/null || true
  wait $HTTP_PID 2>/dev/null || true

  [[ ! -f "$WORK_DIR/app_code.txt" ]] && {
    echo "ERROR: No code received from GitHub (timeout after 120s)"
    echo "  Check: did you click both buttons on GitHub?"
    exit 1
  }

  APP_CODE=$(cat "$WORK_DIR/app_code.txt")
  [[ -z "$APP_CODE" ]] && { echo "ERROR: Code file is empty"; exit 1; }

  echo "  ✅ Authorization code received"
  echo "  Converting manifest code to App credentials..."
  # Single Python process: parse id + write pem atomically — avoids bash holding the raw JSON twice
  APP_ID=$(gh_api -X POST "https://api.github.com/app-manifests/$APP_CODE/conversions" \
    -H "Content-Type: application/json" \
    | PEM_PATH="$PEM_TMPFILE" python3 - <<'PYEOF'
import sys, json, os
d = json.load(sys.stdin)
with open(os.environ["PEM_PATH"], "w") as f:
    f.write(d["pem"])
print(d["id"])
PYEOF
)

  [[ -z "$APP_ID" || "$APP_ID" == "None" ]] && { echo "ERROR: Failed to get App ID"; exit 1; }
  [[ ! -s "$PEM_TMPFILE" ]] && { echo "ERROR: Failed to get private key"; exit 1; }

  echo "  ✅ App created (ID: $APP_ID)"
  echo "  Storing in secrets hub ($SECRETS_HUB_PROJECT)..."

  # Store app ID (create if missing, add version if exists)
  printf '%s' "$APP_ID" | \
    gcloud secrets versions add "$SM_APP_ID" --project="$SECRETS_HUB_PROJECT" --data-file=- 2>/dev/null || \
    printf '%s' "$APP_ID" | \
      gcloud secrets create "$SM_APP_ID" --project="$SECRETS_HUB_PROJECT" \
        --replication-policy=automatic --data-file=-

  # Store app key (add version if exists, create if missing)
  gcloud secrets versions add "$SM_APP_KEY" --project="$SECRETS_HUB_PROJECT" \
    --data-file="$PEM_TMPFILE" 2>/dev/null || \
    gcloud secrets create "$SM_APP_KEY" --project="$SECRETS_HUB_PROJECT" \
      --replication-policy=automatic --data-file="$PEM_TMPFILE"

  shred -uz "$PEM_TMPFILE" 2>/dev/null; touch "$PEM_TMPFILE"
  echo "  ✅ Credentials stored in secrets hub"
  echo "  ✅ Local .pem shredded"
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 2 — Create new GitHub repository from template
# ══════════════════════════════════════════════════════════════
echo ""
echo "── PHASE 2: Create repository ───────────────────────────────"

if gh_api -X GET "https://api.github.com/repos/$ORG/$NEW_REPO" -o /dev/null 2>/dev/null; then
  echo "✅ $ORG/$NEW_REPO already exists"
else
  echo "  Creating $ORG/$NEW_REPO from $TEMPLATE_REPO..."
  gh_api -X POST "https://api.github.com/repos/$TEMPLATE_REPO/generate" \
    -H "Content-Type: application/json" \
    -d "$(ORG="$ORG" NEW_REPO="$NEW_REPO" python3 - <<'PYEOF'
import os, json
print(json.dumps({"owner": os.environ["ORG"], "name": os.environ["NEW_REPO"],
                  "include_all_branches": False, "private": False}))
PYEOF
)" > /dev/null
  echo "  ✅ Created: https://github.com/$ORG/$NEW_REPO"
  sleep 4
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 3 — Terraform: WIF pool + Secret Manager + SA binding
# ══════════════════════════════════════════════════════════════
echo ""
echo "── PHASE 3: Terraform ───────────────────────────────────────"

# Use url.insteadOf to keep the token out of the visible URL in git output
git -c "url.https://x-access-token:${GH_TOKEN}@github.com/.insteadOf=https://github.com/" \
  clone "https://github.com/$ORG/$NEW_REPO.git" "$WORK_DIR/repo" --quiet
cd "$WORK_DIR/repo/terraform"

if ! command -v terraform &>/dev/null; then
  echo "  Installing Terraform 1.9.0..."
  TF_VERSION="1.9.0"
  wget -qO /tmp/tf.zip \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  unzip -q /tmp/tf.zip -d /tmp && sudo mv /tmp/terraform /usr/local/bin/ && rm -f /tmp/tf.zip
fi

cat > terraform.tfvars <<TFVARS
gcp_project_id          = "$GCP_PROJECT"
secrets_hub_project_id  = "$SECRETS_HUB_PROJECT"
github_org              = "$ORG"
repo_name               = "$NEW_REPO"
enable_railway          = $ENABLE_RAILWAY
enable_cloudflare       = $ENABLE_CLOUDFLARE
enable_n8n              = $ENABLE_N8N
project_domain          = "$PROJECT_DOMAIN"
n8n_subdomain           = "$N8N_SUBDOMAIN"
n8n_admin_email         = "$N8N_ADMIN_EMAIL"
TFVARS

# Cloud Shell provides Application Default Credentials — no SA key needed
terraform init -input=false -no-color
echo "  Running Terraform plan..."
terraform plan -input=false -no-color -out=tfplan

if [[ "$AUTO_APPROVE" != "true" ]]; then
  echo ""
  read -rp "  Apply Terraform? Creates WIF pool, SA, and Secret Manager bindings. [y/N]: " TF_CONFIRM
  [[ "${TF_CONFIRM,,}" != "y" ]] && { echo "  Aborted."; exit 0; }
fi

terraform apply -input=false -no-color tfplan
echo "  ✅ Terraform apply complete"

WIF_PROVIDER=$(terraform output -raw workload_identity_provider 2>/dev/null || echo "")
WIF_SA_EMAIL=$(terraform output -raw workload_identity_sa_email  2>/dev/null || echo "")

if [[ -z "$WIF_PROVIDER" || -z "$WIF_SA_EMAIL" ]]; then
  PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" --format='value(projectNumber)')
  [[ -z "$WIF_PROVIDER" ]] && \
    WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
  [[ -z "$WIF_SA_EMAIL" ]] && \
    WIF_SA_EMAIL="github-actions@${GCP_PROJECT}.iam.gserviceaccount.com"
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 4 — Configure GitHub secrets in new repo
# ══════════════════════════════════════════════════════════════
echo ""
echo "── PHASE 4: GitHub secrets ──────────────────────────────────"
echo "  Setting WIF credentials in $ORG/$NEW_REPO..."

set_github_secret "$ORG/$NEW_REPO" "GCP_WORKLOAD_IDENTITY_PROVIDER" "$WIF_PROVIDER"
set_github_secret "$ORG/$NEW_REPO" "GCP_SERVICE_ACCOUNT_EMAIL"      "$WIF_SA_EMAIL"
set_github_secret "$ORG/$NEW_REPO" "GCP_PROJECT_ID"                 "$GCP_PROJECT"
set_github_secret "$ORG/$NEW_REPO" "GCP_SECRETS_HUB_PROJECT"         "$SECRETS_HUB_PROJECT"
set_github_secret "$ORG/$NEW_REPO" "GH_APP_ID"                      "$APP_ID"

echo "  ✅ GitHub secrets configured (WIF + centralized secrets hub)"

# ══════════════════════════════════════════════════════════════
#  PHASE 4.5 — Store Railway / Cloudflare credentials in GCP SM
#  (Only if the respective providers are enabled)
# ══════════════════════════════════════════════════════════════
if [[ "$ENABLE_RAILWAY" == "true" ]] && [[ -n "$RAILWAY_TOKEN" ]]; then
  echo ""
  echo "── PHASE 4.5: Store provider credentials in GCP SM ─────────"

  echo "  Storing Railway API token..."
  store_sm_secret "railway-api-token" "$RAILWAY_TOKEN"

  if [[ "$ENABLE_CLOUDFLARE" == "true" ]] && [[ -n "$CF_TOKEN" ]]; then
    echo "  Storing Cloudflare credentials..."
    store_sm_secret "cloudflare-api-token" "$CF_TOKEN"
    store_sm_secret "cloudflare-zone-id"   "$CF_ZONE_ID"
  fi
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 4.7 — Provision N8N on Railway + Cloudflare DNS
#  (Only if --enable-n8n true)
# ══════════════════════════════════════════════════════════════
if [[ "$ENABLE_N8N" == "true" ]]; then
  echo ""
  echo "── PHASE 4.7: Deploy N8N ────────────────────────────────────"

  # Step A: Generate N8N secrets in GCP SM
  echo "  Triggering populate-secrets.yml (N8N secret generation)..."

  # Poll until GitHub registers the workflow in the new repo (repo creation is async)
  echo "  Waiting for workflows to be available..."
  _wflow_wait=0
  until gh_api -X GET \
    "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/populate-secrets.yml" \
    2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('state')=='active' else 1)" 2>/dev/null; do
    _wflow_wait=$((_wflow_wait + 1))
    [[ $_wflow_wait -ge 12 ]] && { echo "ERROR: Workflows not available after 60s — check $ORG/$NEW_REPO/actions"; exit 1; }
    sleep 5
  done

  gh_api -X POST \
    "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/populate-secrets.yml/dispatches" \
    -H "Content-Type: application/json" -d '{"ref":"main"}' > /dev/null
  echo "  ✅ populate-secrets.yml triggered"

  # Wait for populate-secrets.yml to complete (poll for up to 3 minutes)
  echo "  Waiting for secret generation to complete..."
  WAIT=0
  while [[ $WAIT -lt 18 ]]; do
    sleep 10; WAIT=$((WAIT + 1))
    RUN_STATUS=$(gh_api -X GET \
      "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/populate-secrets.yml/runs?per_page=1" \
      | python3 -c "import sys,json; runs=json.load(sys.stdin).get('workflow_runs',[]); print(runs[0]['conclusion'] if runs else 'pending')" 2>/dev/null || echo "pending")
    [[ "$RUN_STATUS" == "success" ]] && break
    [[ "$RUN_STATUS" == "failure" || "$RUN_STATUS" == "cancelled" ]] && {
      echo "ERROR: populate-secrets.yml failed. Check GitHub Actions logs."
      exit 1
    }
    echo "  Status: $RUN_STATUS (${WAIT}/18)..."
  done

  # Step B: Deploy N8N + create Cloudflare CNAME + create owner account
  echo "  Triggering deploy-n8n.yml..."
  DISPATCH_BODY=$(python3 - <<PYEOF
import json, os
print(json.dumps({
  "ref": "main",
  "inputs": {
    "project_domain":  os.environ.get("PROJECT_DOMAIN", ""),
    "n8n_subdomain":   os.environ.get("N8N_SUBDOMAIN", "n8n"),
    "n8n_admin_email": os.environ.get("N8N_ADMIN_EMAIL", ""),
    "project_name":    os.environ.get("NEW_REPO", "")
  }
}))
PYEOF
)
  PROJECT_DOMAIN="$PROJECT_DOMAIN" N8N_SUBDOMAIN="$N8N_SUBDOMAIN" \
  N8N_ADMIN_EMAIL="$N8N_ADMIN_EMAIL" NEW_REPO="$NEW_REPO" \
  gh_api -X POST \
    "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/deploy-n8n.yml/dispatches" \
    -H "Content-Type: application/json" \
    -d "$DISPATCH_BODY" > /dev/null
  echo "  ✅ deploy-n8n.yml triggered (Railway + Cloudflare + N8N owner setup)"
  echo "  Monitor: https://github.com/$ORG/$NEW_REPO/actions"
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 5 — Trigger autonomous control plane
# ══════════════════════════════════════════════════════════════
echo ""
echo "── PHASE 5: Trigger workflow ────────────────────────────────"

gh_api -X POST \
  "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/autonomous-control-plane.yml/dispatches" \
  -H "Content-Type: application/json" -d '{"ref":"main"}' > /dev/null

echo "  ✅ autonomous-control-plane.yml triggered"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Bootstrap COMPLETE                                      ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf  "║  Repo:    https://github.com/%-28s ║\n" "$ORG/$NEW_REPO"
printf  "║  Actions: https://github.com/%-17s/actions ║\n" "$ORG/$NEW_REPO"
if [[ "$ENABLE_N8N" == "true" ]]; then
printf  "║  N8N:     https://%-39s ║\n" "$N8N_SUBDOMAIN.$PROJECT_DOMAIN"
fi
echo "║                                                          ║"
echo "║  Next: wait for workflows to complete in GitHub Actions  ║"
echo "╚══════════════════════════════════════════════════════════╝"