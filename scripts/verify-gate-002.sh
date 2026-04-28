#!/bin/bash
# verify-gate-002.sh
# GATE-002: Verify GCP WIF pool + provider exist with correct attribute mapping.
#
# Usage: ./scripts/verify-gate-002.sh <gcp-project-id>

set -euo pipefail

GCP_PROJECT="${1:?Usage: $0 <gcp-project-id>}"

echo "--- GATE-002: GCP Workload Identity Federation Pool ---"

# Check WIF pool exists
POOL_STATE=$(gcloud iam workload-identity-pools describe github-pool \
  --project="$GCP_PROJECT" \
  --location=global \
  --format="value(state)" 2>&1) || {
  echo "FAIL: WIF pool 'github-pool' not found in project $GCP_PROJECT"
  echo ""
  echo "Create with:"
  echo "  gcloud iam workload-identity-pools create github-pool \\"
  echo "    --project=$GCP_PROJECT \\"
  echo "    --location=global \\"
  echo "    --display-name='GitHub Actions'"
  exit 1
}

if [[ "$POOL_STATE" != "ACTIVE" ]]; then
  echo "FAIL: WIF pool 'github-pool' state is '$POOL_STATE' (expected ACTIVE)"
  exit 1
fi

echo "  WIF pool: ACTIVE"

# Check WIF provider exists
PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe github-provider \
  --project="$GCP_PROJECT" \
  --location=global \
  --workload-identity-pool=github-pool \
  --format="value(state)" 2>&1) || {
  echo "FAIL: WIF provider 'github-provider' not found"
  echo ""
  echo "Create with:"
  echo "  gcloud iam workload-identity-pools providers create-oidc github-provider \\"
  echo "    --project=$GCP_PROJECT \\"
  echo "    --location=global \\"
  echo "    --workload-identity-pool=github-pool \\"
  echo "    --issuer-uri=https://token.actions.githubusercontent.com \\"
  echo "    --attribute-mapping='google.subject=assertion.sub,assertion.repository=assertion.repository,assertion.ref=assertion.ref'"
  exit 1
}

if [[ "$PROVIDER_STATE" != "ACTIVE" ]]; then
  echo "FAIL: WIF provider state is '$PROVIDER_STATE' (expected ACTIVE)"
  exit 1
fi

echo "  WIF provider: ACTIVE"

# Check issuer URI points to GitHub Actions
ISSUER=$(gcloud iam workload-identity-pools providers describe github-provider \
  --project="$GCP_PROJECT" \
  --location=global \
  --workload-identity-pool=github-pool \
  --format="value(oidc.issuerUri)")

if [[ "$ISSUER" != "https://token.actions.githubusercontent.com" ]]; then
  echo "FAIL: WIF provider issuer URI is '$ISSUER' (expected https://token.actions.githubusercontent.com)"
  exit 1
fi

echo "  Issuer URI: PASS"
echo "PASS: GATE-002 — GCP WIF pool and provider configured"
