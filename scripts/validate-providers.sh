#!/bin/bash
# validate-providers.sh
#
# Runs live validation checks for all configured providers.
# Called by autonomous-control-plane.yml when skip_provider_validation != 'true'.
#
# Environment variables expected (set as GitHub Secrets):
#   GCP_WORKLOAD_IDENTITY_PROVIDER  — already authenticated when this runs in GH Actions
#   GCP_SERVICE_ACCOUNT_EMAIL        — already authenticated
#   GITHUB_APP_ID                    — GitHub App ID
#   ENABLE_RAILWAY (vars)            — 'true' to validate Railway
#   ENABLE_CLOUDFLARE (vars)         — 'true' to validate Cloudflare

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { echo "PASS: $1"; ((PASS_COUNT++)); }
fail() { echo "FAIL: $1"; ((FAIL_COUNT++)); }
skip() { echo "SKIP: $1"; ((SKIP_COUNT++)); }

echo "============================================"
echo "Provider Validation Gates"
echo "============================================"

# --------------------------------------------------------------------------
# Gate V5-A: GCP Secret Manager access
# --------------------------------------------------------------------------
echo ""
echo "--- V5-A: GCP Secret Manager ---"
if gcloud secrets versions access latest --secret="github-app-private-key" &>/dev/null; then
  pass "GCP Secret Manager accessible (github-app-private-key)"
else
  fail "GCP Secret Manager: cannot access github-app-private-key"
fi

# --------------------------------------------------------------------------
# Gate V5-B: GitHub App private key available and valid PEM format
# --------------------------------------------------------------------------
echo ""
echo "--- V5-B: GitHub App Token ---"
if [[ -n "${APP_PRIVATE_KEY:-}" ]] && echo "$APP_PRIVATE_KEY" | grep -q "BEGIN.*PRIVATE KEY"; then
  pass "GitHub App private key loaded from GCP Secret Manager (valid PEM)"
else
  skip "GitHub App private key not available in APP_PRIVATE_KEY env var"
fi

# --------------------------------------------------------------------------
# Gate V5-C: Railway (optional)
# --------------------------------------------------------------------------
echo ""
echo "--- V5-C: Railway Services ---"
if [[ "${ENABLE_RAILWAY:-false}" == "true" ]]; then
  N8N_URL="${N8N_URL:-}"
  if [[ -n "$N8N_URL" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$N8N_URL/healthz" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
      pass "Railway N8N health check (HTTP $HTTP_CODE)"
    else
      fail "Railway N8N health check returned HTTP $HTTP_CODE"
    fi
  else
    skip "N8N_URL not set — Railway may still be initializing"
  fi
else
  skip "Railway disabled (ENABLE_RAILWAY != true)"
fi

# --------------------------------------------------------------------------
# Gate V5-D: Cloudflare Worker (optional)
# --------------------------------------------------------------------------
echo ""
echo "--- V5-D: Cloudflare Webhook Gateway ---"
if [[ "${ENABLE_CLOUDFLARE:-false}" == "true" ]]; then
  WORKER_URL="${CLOUDFLARE_WORKER_URL:-}"
  WEBHOOK_SECRET_VAL=$(gcloud secrets versions access latest --secret="webhook-secret" 2>/dev/null || echo "")
  if [[ -n "$WORKER_URL" && -n "$WEBHOOK_SECRET_VAL" ]]; then
    PAYLOAD='{"test":"validation"}'
    SIG="sha256=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET_VAL" | awk '{print $2}')"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
      -X POST \
      -H "X-Hub-Signature-256: $SIG" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "$WORKER_URL/webhook" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "202" ]]; then
      pass "Cloudflare HMAC validation (HTTP $HTTP_CODE)"
    else
      fail "Cloudflare HMAC test returned HTTP $HTTP_CODE"
    fi
  else
    skip "Cloudflare worker URL or webhook secret not available yet"
  fi
else
  skip "Cloudflare disabled (ENABLE_CLOUDFLARE != true)"
fi

# --------------------------------------------------------------------------
# Gate V5-E: GitHub API rate limit check
# --------------------------------------------------------------------------
echo ""
echo "--- V5-E: GitHub API connectivity ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
  "https://api.github.com/rate_limit" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "GitHub API accessible (HTTP $HTTP_CODE)"
else
  fail "GitHub API check failed (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================"
echo "Results: ${PASS_COUNT} PASS  |  ${FAIL_COUNT} FAIL  |  ${SKIP_COUNT} SKIP"
echo "============================================"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "ERROR: $FAIL_COUNT validation gate(s) failed"
  exit 1
fi

echo "All validation gates passed (or skipped)"
