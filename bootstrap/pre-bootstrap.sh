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
#   4. Paste back the redirect URL when prompted
#   5. Confirm Terraform apply when prompted (or pass --yes to skip)
#
# Usage:
#   export GH_TOKEN="ghp_..."
#   bash bootstrap/pre-bootstrap.sh --new-repo MY_PROJECT_NAME
#
# Optional overrides (auto-detected if omitted):
#   --gcp-project  GCP_PROJECT_ID  (default: current gcloud project)
#   --org          GITHUB_ORG      (default: owner of this template repo)
#   --enable-railway    true|false
#   --enable-cloudflare true|false
#   --enable-n8n        true|false
#   --yes                           (skip Terraform confirm)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ORG=""; GCP_PROJECT=""; NEW_REPO=""
ENABLE_RAILWAY="false"; ENABLE_CLOUDFLARE="false"; ENABLE_N8N="false"
AUTO_APPROVE="${AUTO_APPROVE:-false}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --org)               ORG="$2";               shift 2 ;;
    --gcp-project)       GCP_PROJECT="$2";        shift 2 ;;
    --new-repo)          NEW_REPO="$2";           shift 2 ;;
    --enable-railway)    ENABLE_RAILWAY="$2";     shift 2 ;;
    --enable-cloudflare) ENABLE_CLOUDFLARE="$2";  shift 2 ;;
    --enable-n8n)        ENABLE_N8N="$2";         shift 2 ;;
    --yes|-y)            AUTO_APPROVE="true";     shift   ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

GH_TOKEN="${GH_TOKEN:-}"
[[ -z "$GH_TOKEN" ]] && { echo "ERROR: GH_TOKEN is not set"; exit 1; }

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

gh_api() {
  local METHOD="$1"; shift
  curl -sf -X "$METHOD" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

set_github_secret() {
  local REPO="$1" NAME="$2" VALUE="$3"
  if command -v gh &>/dev/null; then
    printf '%s' "$VALUE" | gh secret set "$NAME" --repo "$REPO"
    echo "  ✅ $NAME"
    return
  fi
  SECRET_VALUE="$VALUE" SECRET_REPO="$REPO" SECRET_NAME="$NAME" \
  python3 - <<'PYEOF'
import os, json, urllib.request
from nacl import encoding, public

repo  = os.environ["SECRET_REPO"]
name  = os.environ["SECRET_NAME"]
value = os.environ["SECRET_VALUE"]
token = os.environ["GH_TOKEN"]

hdrs = {"Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"}

req = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/actions/secrets/public-key",
    headers=hdrs)
with urllib.request.urlopen(req) as r:
    key_data = json.load(r)

pub_key   = public.PublicKey(key_data["key"].encode(), encoding.Base64Encoder())
encrypted = public.SealedBox(pub_key).encrypt(
                value.encode(), encoding.Base64Encoder()).decode()

body = json.dumps({"encrypted_value": encrypted, "key_id": key_data["key_id"]}).encode()
req = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/actions/secrets/{name}",
    data=body, method="PUT",
    headers={**hdrs, "Content-Type": "application/json"})
urllib.request.urlopen(req)
print(f"  ✅ {os.environ['SECRET_NAME']}")
PYEOF
}

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

if gcloud secrets describe "$SM_APP_ID"  --project="$GCP_PROJECT" &>/dev/null \
&& gcloud secrets describe "$SM_APP_KEY" --project="$GCP_PROJECT" &>/dev/null; then
  echo "✅ GitHub App credentials already in GCP Secret Manager — skipping"
  APP_ID=$(gcloud secrets versions access latest \
    --secret="$SM_APP_ID" --project="$GCP_PROJECT")
else
  # Compact JSON manifest (short URL to avoid query-string limits)
  MANIFEST_ENC=$(ORG="$ORG" python3 - <<'PYEOF'
import os, json, urllib.parse
org = os.environ["ORG"]
m = {
  "name": f"{org}-agent",
  "url":  f"https://github.com/{org}",
  "hook_attributes": {"url": "https://placeholder.example.com", "active": False},
  "redirect_url": "https://github.com/settings/apps",
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
  echo "  ACTION REQUIRED — two steps:"
  echo ""
  echo "  Step 1: Open this URL in your browser:"
  echo ""
  echo "    $APP_URL"
  echo ""
  echo "  Step 2: Click 'Create GitHub App' on the GitHub page"
  echo ""
  echo "  GitHub will redirect you to a URL like:"
  echo "    https://github.com/settings/apps?code=XXXXXXXXXX&state=${STATE}"
  echo ""
  echo "  Copy the FULL URL from your browser address bar and paste it below."
  echo ""
  read -rp "  Redirect URL: " REDIRECT_URL

  APP_CODE=$(REDIRECT_URL="$REDIRECT_URL" python3 - <<'PYEOF'
import os
from urllib.parse import urlparse, parse_qs
url = os.environ["REDIRECT_URL"].strip()
qs  = parse_qs(urlparse(url).query)
codes = qs.get("code", [])
if not codes:
    import sys; sys.exit(f"ERROR: No code= found in URL: {url}")
print(codes[0])
PYEOF
)

  echo "  Converting manifest code to App credentials..."
  # Single Python process: parse id + write pem atomically — avoids bash holding the raw JSON twice
  APP_ID=$(gh_api POST "https://api.github.com/app-manifests/$APP_CODE/conversions" \
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
  echo "  Storing in GCP Secret Manager..."

  printf '%s' "$APP_ID" | \
    gcloud secrets create "$SM_APP_ID" --project="$GCP_PROJECT" \
      --replication-policy=automatic --data-file=- 2>/dev/null \
    || printf '%s' "$APP_ID" | \
       gcloud secrets versions add "$SM_APP_ID" --project="$GCP_PROJECT" --data-file=-

  gcloud secrets create "$SM_APP_KEY" --project="$GCP_PROJECT" \
    --replication-policy=automatic --data-file="$PEM_TMPFILE" 2>/dev/null \
    || gcloud secrets versions add "$SM_APP_KEY" --project="$GCP_PROJECT" \
       --data-file="$PEM_TMPFILE"

  shred -uz "$PEM_TMPFILE" 2>/dev/null; touch "$PEM_TMPFILE"
  echo "  ✅ Credentials stored in GCP Secret Manager"
  echo "  ✅ Local .pem shredded"
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 2 — Create new GitHub repository from template
# ══════════════════════════════════════════════════════════════
echo ""
echo "── PHASE 2: Create repository ───────────────────────────────"

if gh_api GET "https://api.github.com/repos/$ORG/$NEW_REPO" -o /dev/null 2>/dev/null; then
  echo "✅ $ORG/$NEW_REPO already exists"
else
  echo "  Creating $ORG/$NEW_REPO from $TEMPLATE_REPO..."
  gh_api POST "https://api.github.com/repos/$TEMPLATE_REPO/generate" \
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
gcp_project        = "$GCP_PROJECT"
github_org         = "$ORG"
github_repo        = "$NEW_REPO"
enable_railway     = $ENABLE_RAILWAY
enable_cloudflare  = $ENABLE_CLOUDFLARE
enable_n8n         = $ENABLE_N8N
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

echo "  ✅ GitHub secrets configured (WIF only — no SA key stored)"

# ══════════════════════════════════════════════════════════════
#  PHASE 5 — Trigger autonomous control plane
# ══════════════════════════════════════════════════════════════
echo ""
echo "── PHASE 5: Trigger workflow ────────────────────────────────"

gh_api POST \
  "https://api.github.com/repos/$ORG/$NEW_REPO/actions/workflows/autonomous-control-plane.yml/dispatches" \
  -H "Content-Type: application/json" -d '{"ref":"main"}' > /dev/null

echo "  ✅ autonomous-control-plane.yml triggered"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Bootstrap COMPLETE                                      ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf  "║  Repo:    https://github.com/%-28s ║\n" "$ORG/$NEW_REPO"
printf  "║  Actions: https://github.com/%-17s/actions ║\n" "$ORG/$NEW_REPO"
echo "║                                                          ║"
echo "║  Next: wait for autonomous-control-plane.yml to pass    ║"
echo "║  all ADR checks and create ADR-0200 project charter.    ║"
echo "╚══════════════════════════════════════════════════════════╝"



