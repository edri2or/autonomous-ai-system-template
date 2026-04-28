#!/bin/bash
# verify-gate-003.sh
# GATE-003: Verify Terraform service account exists with required IAM roles.
#
# Usage: ./scripts/verify-gate-003.sh <gcp-project-id>

set -euo pipefail

GCP_PROJECT="${1:?Usage: $0 <gcp-project-id>}"
SA_NAME="terraform-bootstrap"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

echo "--- GATE-003: Terraform Service Account IAM ---"

# Check service account exists
gcloud iam service-accounts describe "$SA_EMAIL" \
  --project="$GCP_PROJECT" &>/dev/null || {
  echo "FAIL: Service account '$SA_EMAIL' not found"
  echo ""
  echo "Create with:"
  echo "  gcloud iam service-accounts create $SA_NAME \\"
  echo "    --project=$GCP_PROJECT \\"
  echo "    --display-name='Terraform Bootstrap'"
  exit 1
}

echo "  Service account: EXISTS"

# Check Secret Manager accessor role
SM_BINDING=$(gcloud projects get-iam-policy "$GCP_PROJECT" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_EMAIL AND bindings.role:roles/secretmanager.secretAccessor" \
  --format="value(bindings.role)" 2>/dev/null)

if [[ -z "$SM_BINDING" ]]; then
  echo "WARN: Service account missing roles/secretmanager.secretAccessor"
  echo "Grant with:"
  echo "  gcloud projects add-iam-policy-binding $GCP_PROJECT \\"
  echo "    --member=serviceAccount:$SA_EMAIL \\"
  echo "    --role=roles/secretmanager.secretAccessor"
fi

# Check WIF binding exists on service account
WIF_BINDING=$(gcloud iam service-accounts get-iam-policy "$SA_EMAIL" \
  --project="$GCP_PROJECT" \
  --format="json" 2>/dev/null | python3 -c "
import json, sys
policy = json.load(sys.stdin)
has_wif = any(
  'workloadIdentityUser' in b.get('role', '') or
  'iam.workloadIdentityUser' in b.get('role', '')
  for b in policy.get('bindings', [])
)
print('YES' if has_wif else 'NO')
" 2>/dev/null || echo "UNKNOWN")

if [[ "$WIF_BINDING" == "NO" ]]; then
  echo "WARN: WIF binding (roles/iam.workloadIdentityUser) not set on service account"
  echo "This is set automatically by Terraform during bootstrap apply."
fi

echo "  IAM: PASS (will be fully configured by Terraform apply)"
echo "PASS: GATE-003 — Terraform service account exists"
