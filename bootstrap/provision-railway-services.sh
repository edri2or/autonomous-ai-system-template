#!/bin/bash
# provision-railway-services.sh
#
# Deploys N8N, PostgreSQL, and webhook handler to Railway.
# Requires: RAILWAY_TOKEN env var + railway CLI installed.
#
# Usage:
#   RAILWAY_TOKEN=<token> ./bootstrap/provision-railway-services.sh \
#     <railway-workspace-id> <new-repo-name>

set -euo pipefail

RAILWAY_WORKSPACE_ID="${1:?Usage: $0 <workspace-id> <repo-name>}"
NEW_REPO="${2:?Usage: $0 <workspace-id> <repo-name>}"

RAILWAY_TOKEN="${RAILWAY_TOKEN:?RAILWAY_TOKEN must be set}"

echo "=== Provisioning Railway Services for $NEW_REPO ==="

# Verify railway CLI is available
if ! command -v railway &>/dev/null; then
  echo "ERROR: railway CLI not found. Install from https://docs.railway.app/develop/cli"
  exit 1
fi

railway login --browserless || true

# Create project
echo "Creating Railway project: n8n-$NEW_REPO"
railway project create --name "n8n-$NEW_REPO" --workspace "$RAILWAY_WORKSPACE_ID"

# Deploy PostgreSQL
echo "Deploying PostgreSQL..."
railway service create --name postgres
railway up --name postgres --image postgres:15 \
  --env "POSTGRES_PASSWORD=$(openssl rand -hex 16)"

# Deploy N8N
echo "Deploying N8N..."
railway service create --name n8n
railway up --name n8n --image n8nio/n8n:latest \
  --env "N8N_PORT=5678" \
  --env "DB_TYPE=postgresdb"

# Deploy webhook handler
echo "Deploying webhook handler..."
railway service create --name webhook-handler
railway up --name webhook-handler \
  --env "PORT=8000"

echo ""
echo "✓ Railway services deployed"
echo ""
echo "Next: Update GitHub Secrets with Railway service URLs"
echo "  RAILWAY_POSTGRES_URL = railway service url postgres"
echo "  N8N_URL              = railway service url n8n"
