#!/bin/bash
# verify-gate-001.sh
# GATE-001: Verify GitHub App exists and github-app-private-key secret is in GCP Secret Manager.
#
# Usage: ./scripts/verify-gate-001.sh <gcp-project-id>

set -euo pipefail

GCP_PROJECT="${1:?Usage: $0 <gcp-project-id>}"

echo "--- GATE-001: GitHub App Private Key in GCP Secret Manager ---"

# Check GCP credentials available
if ! gcloud auth print-access-token &>/dev/null; then
  echo "FAIL: No GCP credentials. Run: gcloud auth application-default login"
  exit 1
fi

# Check secret exists and has at least one version
VERSION=$(gcloud secrets versions list github-app-private-key \
  --project="$GCP_PROJECT" \
  --format="value(name)" \
  --limit=1 2>&1) || {
  echo "FAIL: Secret 'github-app-private-key' not found in project $GCP_PROJECT"
  echo ""
  echo "Manual action required:"
  echo "  1. Go to GitHub Developer Settings → Apps → Your App → Private keys"
  echo "  2. Generate and download the .pem file"
  echo "  3. Run: gcloud secrets create github-app-private-key --replication-policy=automatic --data-file=app-key.pem"
  exit 1
}

if [[ -z "$VERSION" ]]; then
  echo "FAIL: Secret 'github-app-private-key' exists but has no versions"
  exit 1
fi

# Check github-app-id secret exists
gcloud secrets versions access latest \
  --secret="github-app-id" \
  --project="$GCP_PROJECT" &>/dev/null || {
  echo "FAIL: Secret 'github-app-id' not found. Create with:"
  echo "  gcloud secrets create github-app-id --replication-policy=automatic"
  echo "  echo -n '<app-id>' | gcloud secrets versions add github-app-id --data-file=-"
  exit 1
}

echo "PASS: GATE-001 — GitHub App secrets present in GCP Secret Manager"
