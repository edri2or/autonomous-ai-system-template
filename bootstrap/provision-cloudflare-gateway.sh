#!/bin/bash
# provision-cloudflare-gateway.sh
#
# Deploys HMAC-validating webhook gateway as a Cloudflare Worker.
# Requires: CLOUDFLARE_API_TOKEN env var + wrangler CLI installed.
#
# Usage:
#   CLOUDFLARE_API_TOKEN=<token> ./bootstrap/provision-cloudflare-gateway.sh \
#     <zone-id> <repo-name> <backend-url>

set -euo pipefail

ZONE_ID="${1:?Usage: $0 <zone-id> <repo-name> <backend-url>}"
REPO_NAME="${2:?Usage: $0 <zone-id> <repo-name> <backend-url>}"
BACKEND_URL="${3:?Usage: $0 <zone-id> <repo-name> <backend-url>}"

CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-$(openssl rand -hex 24)}"

echo "=== Provisioning Cloudflare Gateway for $REPO_NAME ==="

# Verify wrangler is available
if ! command -v wrangler &>/dev/null; then
  echo "ERROR: wrangler CLI not found. Install with: npm install -g wrangler"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WORKER_DIR="$ROOT_DIR/terraform/modules/cloudflare-gateway"

# Generate wrangler.toml
cat > "$WORKER_DIR/wrangler.toml" << WRANGLER
name = "webhook-gateway-${REPO_NAME}"
main = "webhook-gateway.js"
compatibility_date = "2024-01-01"

[vars]
BACKEND_URL = "${BACKEND_URL}"
WRANGLER

echo "Deploying Cloudflare Worker: webhook-gateway-$REPO_NAME"
cd "$WORKER_DIR"
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" wrangler secret put WEBHOOK_SECRET <<< "$WEBHOOK_SECRET"
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" wrangler deploy

echo ""
echo "✓ Cloudflare Worker deployed"
echo ""
echo "Webhook secret (store in GCP Secret Manager):"
echo "  gcloud secrets create webhook-secret --data-file=- <<< \"\$WEBHOOK_SECRET\""
echo ""
echo "Configure GitHub webhook at:"
echo "  https://github.com/settings/hooks"
echo "  URL: https://webhooks.your-domain/webhook"
echo "  Secret: \$WEBHOOK_SECRET"
