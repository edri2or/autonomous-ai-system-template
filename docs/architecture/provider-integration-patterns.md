# Provider Integration Patterns

**Date:** 2026-04-28  
**Related Primary Document:** docs/state/architecture-phase-6.md (overview)  
**Purpose:** Integration specifications for cloud providers and external APIs  
**Audience:** Infrastructure engineers, security reviewers, operators

---

## Overview

The template integrates with multiple cloud providers and external APIs. Each provider has:
- **Evidence:** Proven in source repos (Currently Proven, Historically Proven, or Needs Validation)
- **Configuration:** Terraform IaC + GitHub Secrets
- **Validation:** Phase 7-9 automated gates
- **Fallback:** Support for disabling optional providers

---

## Required Providers

### 1. Google Cloud Platform (GCP) — REQUIRED

**Evidence:** Currently Proven in 5 of 7 repos ✅

**Purpose:** 
- Workload Identity Federation (WIF) for keyless GitHub auth
- Secret Manager for credential storage
- Service account IAM for fine-grained permissions

**Architecture:**

```
GitHub Actions Workflow
    ↓
actions/id-token@v1 → Generate GitHub OIDC token
    ↓
google-github-actions/auth@v2 → Exchange OIDC for GCP service account token (via WIF)
    ↓
gcloud CLI → Access Secret Manager (no stored keys)
    ↓
Read GitHub App private key from Secret Manager
    ↓
actions/create-github-app-token@v1 → Mint ephemeral 10-min JWT + 1-hour token
    ↓
curl + Bearer token → GitHub API calls
```

**Configuration:**

**Terraform (terraform/wif.tf):**
```hcl
# WIF Pool
resource "google_iam_workload_identity_pool" "github" {
  provider = google
  project  = var.gcp_project_id
  
  workload_identity_pool_id = "github-pool"
  location                  = "global"
  display_name              = "GitHub Actions"
}

# WIF Provider (with branch scoping per ADR-0103)
resource "google_iam_workload_identity_pool_provider" "github" {
  provider = google
  project  = var.gcp_project_id
  
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  location                           = "global"
  display_name                       = "GitHub Provider"
  
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "assertion.aud"                 = "assertion.aud"
    "assertion.repository"          = "assertion.repository"
    "assertion.repository_owner"    = "assertion.repository_owner"
    "assertion.ref"                 = "assertion.ref"  # Branch reference
  }
  
  attribute_condition = "assertion.repository == 'github.com/${var.github_org}/${local.repo_name}' && assertion.ref == 'refs/heads/main'"
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service Account for Terraform
resource "google_service_account" "terraform" {
  project      = var.gcp_project_id
  account_id   = "terraform-bootstrap"
  display_name = "Terraform Bootstrap SA"
}

# WIF binding: GitHub OIDC → Service Account
resource "google_service_account_iam_binding" "wif_binding" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  
  members = [
    "principalSet://goog/github/repo_owner/${var.github_org}",
  ]
}

# Grant Secret Manager permissions
resource "google_project_iam_member" "secret_manager" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

output "workload_identity_provider" {
  value = "projects/${data.google_client_config.current.project_number}/locations/${google_iam_workload_identity_pool_provider.github.location}/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
  description = "WIF provider resource name (used in GitHub Secrets)"
}

output "wif_provider_resource_name" {
  value = "projects/${data.google_client_config.current.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
  description = "WIF provider resource name (used by bootstrap scripts)"
}

output "service_account_email" {
  value = google_service_account.terraform.email
  description = "Terraform service account email (used in GitHub Secrets)"
}
```

**Terraform (terraform/secrets.tf):**
```hcl
# GitHub App Private Key (stored securely)
# IMPORTANT: This secret MUST be pre-populated in GCP Secret Manager before Terraform runs
# Create manually: gcloud secrets create github-app-private-key --data-file=app-key.pem
# OR load from existing GCP secret version

resource "google_secret_manager_secret" "github_app_private_key" {
  project   = var.gcp_project_id
  secret_id = "github-app-private-key"
  
  labels = {
    purpose = "github-app-auth"
    managed = "terraform"
  }
}

# Reference existing secret version (DO NOT create new version here)
# Bootstrap script fetches this via gcloud secrets versions access latest
data "google_secret_manager_secret_version" "github_app_private_key" {
  secret = google_secret_manager_secret.github_app_private_key.id
  version = "latest"
}

# Grant access to service account
resource "google_secret_manager_secret_iam_member" "github_app_key_access" {
  secret_id = google_secret_manager_secret.github_app_private_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}
```

**Pre-Bootstrap Setup (required):**
```bash
# Download GitHub App private key from GitHub Developer Settings (UI)
# Save as: app-key.pem

# Create Secret Manager secret with the key
gcloud secrets create github-app-private-key \
  --replication-policy="automatic" \
  --data-file=app-key.pem

# Verify it was created
gcloud secrets versions access latest --secret="github-app-private-key"

# IMPORTANT: Add app-key.pem and any local secret files to .gitignore
echo "app-key.pem" >> .gitignore
echo "secrets/" >> .gitignore
```

**GitHub Workflow (actions/auth@v2):**
```yaml
- uses: google-github-actions/auth@v2
  id: google-auth
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account_email: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
    token_format: 'access_token'
    access_token_lifetime: '600s'

- uses: google-github-actions/setup-gcloud@v2

- name: Retrieve GitHub App Private Key
  run: |
    gcloud secrets versions access latest --secret="github-app-private-key" > /tmp/app-key.pem
    chmod 600 /tmp/app-key.pem
```

**Validation Gate (Phase 7-9):**
```bash
#!/bin/bash
# Validate GCP WIF token exchange works

WIF_PROVIDER="$1"
SA_EMAIL="$2"

# Use GitHub OIDC token to exchange for GCP token
GITHUB_TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://iamcredentials.googleapis.com/$WIF_PROVIDER" \
  | jq -r '.value')

# Exchange for access token
ACCESS_TOKEN=$(curl -sS -X POST \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SA_EMAIL:generateAccessToken" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"lifetime": "600s"}' \
  | jq -r '.accessToken')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
  echo "FAIL: GCP WIF token exchange failed"
  exit 1
fi

echo "PASS: GCP WIF token exchange successful"
```

---

### 2. GitHub — REQUIRED

**Evidence:** Currently Proven in all 7 repos ✅

**Purpose:**
- Source control + CI/CD via GitHub Actions
- GitHub App for keyless API authentication
- Webhook delivery for event-driven automation

**Configuration:**

**GitHub App (terraform/github-app.tf):**
```hcl
# Note: GitHub App must be created manually in GitHub UI
# This Terraform only installs it on the repo and grants permissions

resource "github_app_installation" "repo" {
  app_id           = var.github_app_id
  target_id        = github_repository.main.id
  target_type      = "Repository"
}

# Permissions can be configured at app creation time
# Required permissions:
# - Contents: Read & Write (push + PR merges)
# - Actions: Read & Write (trigger workflows)
# - Checks: Read & Write (report job status)
# - Metadata: Read (repo info)
```

**GitHub Actions Workflow:**
```yaml
- uses: actions/id-token@v1
  id: oidc-token
  with:
    audience: 'https://token.actions.githubusercontent.com'

- uses: actions/create-github-app-token@v1
  id: github-token
  with:
    app-id: ${{ secrets.GITHUB_APP_ID }}
    private-key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}

- name: API Call with GitHub App Token
  run: |
    curl -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${{ steps.github-token.outputs.token }}" \
      https://api.github.com/repos/${{ github.repository }}/dispatches \
      -d '{"event_type": "autonomous-trigger"}'
```

**Validation Gate (Phase 7-9):**
```bash
#!/bin/bash
# Validate GitHub App token minting works

APP_ID="$1"
PRIVATE_KEY="$2"

# Create JWT
HEADER='{"alg":"RS256","typ":"JWT"}'
NOW=$(date +%s)
EXP=$((NOW + 600))
PAYLOAD="{\"iat\":$NOW,\"exp\":$EXP,\"iss\":\"$APP_ID\"}"

# (Simplified—actual JWT generation uses openssl)

# Mint installation token
INSTALL_TOKEN=$(curl -sS -X POST \
  "https://api.github.com/app/installations/$(get_app_installation_id)/access_tokens" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  | jq -r '.token')

if [ -z "$INSTALL_TOKEN" ] || [ "$INSTALL_TOKEN" == "null" ]; then
  echo "FAIL: GitHub App token minting failed"
  exit 1
fi

echo "PASS: GitHub App token minting successful"
```

---

## Optional Providers

### 3. Railway — OPTIONAL (enable_railway = true)

**Evidence:** Historically Proven in 5 of 7 repos ✅

**Purpose:**
- Platform-as-a-Service for microservices
- Postgres database hosting
- N8N workflow engine deployment
- Always-on webhook handlers

**Configuration:**

**Terraform (terraform/modules/railway-services/main.tf):**
```hcl
terraform {
  required_providers {
    railway = {
      source = "brainly/railway"
      version = "~> 0.2"
    }
  }
}

# Railway environment (project)
resource "railway_environment" "main" {
  name       = var.environment_name
  project_id = var.railway_project_id
}

# PostgreSQL service
resource "railway_service" "postgres" {
  count = var.enable_postgresql ? 1 : 0
  
  name    = "postgres"
  owner_id = railway_environment.main.id
  source {
    image = "postgres:15"
  }
  
  config = {
    PORT          = "5432"
    POSTGRES_PASSWORD = random_password.postgres.result
  }
}

# N8N service
resource "railway_service" "n8n" {
  count = var.enable_n8n ? 1 : 0
  
  name    = "n8n"
  owner_id = railway_environment.main.id
  source {
    image = "n8nio/n8n:latest"
  }
  
  config = {
    N8N_HOST = var.railway_domain
    N8N_PORT = "5678"
    DB_TYPE  = "postgresdb"
  }
  
  depends_on = [railway_service.postgres]
}

# Webhook handler service
resource "railway_service" "webhook_handler" {
  count = var.enable_webhooks ? 1 : 0
  
  name    = "webhook-handler"
  owner_id = railway_environment.main.id
  source {
    path = "webhook-handler/"  # Nixpacks auto-detects Python
  }
  
  config = {
    PORT = "8000"
    GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
  }
}

output "postgres_connection_string" {
  value = railway_service.postgres[0].connection_string
  sensitive = true
}

output "n8n_url" {
  value = railway_service.n8n[0].public_url
}
```

**GitHub Secret for Railway Token:**
```bash
gh secret set RAILWAY_API_TOKEN --body "$RAILWAY_TOKEN"
```

**Validation Gate (Phase 7-9):**
```bash
#!/bin/bash
# Validate Railway services are healthy

RAILWAY_TOKEN="$1"
N8N_URL="$2"

# Health check N8N
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$N8N_URL/healthz")

if [ "$HTTP_CODE" != "200" ]; then
  echo "FAIL: N8N health check returned $HTTP_CODE"
  exit 1
fi

echo "PASS: Railway services are healthy"
```

---

### 4. Cloudflare Workers — OPTIONAL (enable_cloudflare = true)

**Evidence:** Historically Proven in 4 of 7 repos ✅

**Purpose:**
- Edge gateway for webhook validation
- HMAC signature verification
- Request routing + rate limiting
- SSL/TLS termination

**Configuration:**

**Terraform (terraform/modules/cloudflare-gateway/main.tf):**
```hcl
terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Cloudflare Worker Script
resource "cloudflare_workers_script" "webhook_gateway" {
  name    = "webhook-gateway-${var.repo_name}"
  account_id = var.cloudflare_account_id
  
  content = file("${path.module}/webhook-gateway.js")
  
  plain_text_binding {
    name = "WEBHOOK_SECRET"
    text = var.github_webhook_secret
  }
  
  plain_text_binding {
    name = "BACKEND_URL"
    text = var.backend_url
  }
}

# Route: bind worker to domain
resource "cloudflare_workers_route" "webhook" {
  zone_id      = var.cloudflare_zone_id
  pattern      = "webhooks.${var.domain}/*"
  script_name  = cloudflare_workers_script.webhook_gateway.name
}

# API token for automation (token rotation)
resource "cloudflare_api_token" "automation" {
  name = "automation-token-${var.repo_name}"
  
  condition {
    request_ip {
      in = [var.github_actions_ip_cidr]  # Restrict to GitHub IP ranges
    }
  }
  
  policies = [{
    permission_groups = [
      data.cloudflare_api_token_permission_groups.permissions["api_tokens"].id,
      data.cloudflare_api_token_permission_groups.permissions["zone_settings"].id,
    ]
    resources = {
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    }
  }]
}

resource "google_secret_manager_secret" "cloudflare_token" {
  project   = var.gcp_project_id
  secret_id = "cloudflare-api-token"
}

resource "google_secret_manager_secret_version" "cloudflare_token" {
  secret      = google_secret_manager_secret.cloudflare_token.id
  secret_data = cloudflare_api_token.automation.token
}

output "cloudflare_worker_url" {
  value = "https://webhooks.${var.domain}"
}
```

**Cloudflare Worker Script (webhook-gateway.js):**
```javascript
import { createHmac } from 'crypto';

export default {
  async fetch(request, env) {
    // Only allow POST
    if (request.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    // Verify HMAC signature
    const signature = request.headers.get('x-hub-signature-256');
    const body = await request.text();
    
    const hmac = createHmac('sha256', env.WEBHOOK_SECRET);
    hmac.update(body);
    const expected = 'sha256=' + hmac.digest('hex');
    
    if (signature !== expected) {
      return new Response('Signature verification failed', { status: 401 });
    }

    // Forward to backend
    const backend_request = new Request(env.BACKEND_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-forwarded-for': request.headers.get('cf-connecting-ip'),
      },
      body: body,
    });

    return fetch(backend_request);
  }
};
```

**Token Rotation Workflow (.github/workflows/rotate-cf-token.yml):**
```yaml
name: Rotate Cloudflare Token
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly, Sunday midnight

permissions:
  id-token: write

jobs:
  rotate:
    runs-on: ubuntu-latest
    steps:
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account_email: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      
      - uses: google-github-actions/setup-gcloud@v2
      
      - name: Rotate Cloudflare Token
        run: |
          # Create new token
          NEW_TOKEN=$(curl -s -X POST \
            https://api.cloudflare.com/client/v4/accounts/${{ secrets.CLOUDFLARE_ACCOUNT_ID }}/tokens \
            -H "Authorization: Bearer ${{ secrets.CLOUDFLARE_EXISTING_TOKEN }}" \
            -H "Content-Type: application/json" \
            -d '{"name":"automation-token-rotated","policies":[...]}' \
            | jq -r '.result.id')
          
          # Store in GCP Secret Manager
          gcloud secrets versions add cloudflare-api-token --data-file=/dev/stdin <<< "$NEW_TOKEN"
          
          # Delete old token
          curl -s -X DELETE \
            https://api.cloudflare.com/client/v4/accounts/${{ secrets.CLOUDFLARE_ACCOUNT_ID }}/tokens/${{ secrets.CLOUDFLARE_OLD_TOKEN_ID }} \
            -H "Authorization: Bearer ${{ secrets.CLOUDFLARE_EXISTING_TOKEN }}"
```

**Validation Gate (Phase 7-9):**
```bash
#!/bin/bash
# Validate Cloudflare HMAC verification works

WEBHOOK_SECRET="$1"
WORKER_URL="$2"

# Create test payload
PAYLOAD='{"test":"data"}'
SIGNATURE="sha256=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $2}')"

# Send to Cloudflare Worker
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "X-Hub-Signature-256: $SIGNATURE" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$WORKER_URL/webhook")

if [ "$HTTP_CODE" != "200" ]; then
  echo "FAIL: Cloudflare Worker HMAC test returned $HTTP_CODE"
  exit 1
fi

echo "PASS: Cloudflare HMAC verification working"
```

---

### 5. N8N Automation Engine — OPTIONAL (enable_n8n = true)

**Evidence:** Historically Proven in project-life-130 (Stage 6 green) ⚠

**Purpose:**
- Multi-agent routing (Telegram → appropriate agent)
- Workflow orchestration for complex processes
- Integration with Claude API + external services
- Audit trail for decision-making

**Configuration:**

**Terraform (terraform/modules/n8n-workflows/main.tf):**
```hcl
# N8N workflows are version-controlled as JSON
resource "railway_service" "n8n" {
  # ... (see Railway section above)
}

# Workflow files (stored in .github/workflows/n8n/)
# These are imported into N8N at deployment time

locals {
  workflows = {
    "multi-agent-router.json"       = file("${path.module}/workflows/multi-agent-router.json")
    "code-agent-workflow.json"      = file("${path.module}/workflows/code-agent-workflow.json")
    "infra-agent-workflow.json"     = file("${path.module}/workflows/infra-agent-workflow.json")
    "ops-agent-workflow.json"       = file("${path.module}/workflows/ops-agent-workflow.json")
    "research-agent-workflow.json"  = file("${path.module}/workflows/research-agent-workflow.json")
  }
}

# Upload workflows to N8N (would require N8N API access)
```

**Validation Gate (Phase 7-9):**
```bash
#!/bin/bash
# Validate N8N workflows are accessible

N8N_URL="$1"
N8N_API_KEY="$2"

# List workflows
WORKFLOWS=$(curl -s -X GET \
  "$N8N_URL/api/v1/workflows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  | jq '.data | length')

if [ "$WORKFLOWS" -lt 5 ]; then
  echo "FAIL: Expected 5+ workflows, found $WORKFLOWS"
  exit 1
fi

echo "PASS: N8N workflows loaded successfully"
```

---

### 6. External APIs (OpenRouter, Linear, OpenCode) — OPTIONAL

**Evidence:** Needs Validation / Rejected ⚠

**Configuration Pattern (ADR-0104):**

For any external API that requires authentication:

**WRONG (tokens exposed in logs):**
```python
requests.post("https://api.example.com/v1/call",
    json={"API_KEY": secret_token, ...})
```

**RIGHT (tokens in Authorization header):**
```python
requests.post("https://api.example.com/v1/call",
    headers={"Authorization": f"Bearer {secret_token}"},
    json={"prompt": ..., ...})
```

**External API Template (Terraform):**
```hcl
# Store external API token in GCP Secret Manager
resource "google_secret_manager_secret" "external_api_token" {
  project   = var.gcp_project_id
  secret_id = "external-api-token"  # e.g., openrouter-api-token
}

resource "google_secret_manager_secret_version" "external_api_token" {
  secret      = google_secret_manager_secret.external_api_token.id
  secret_data = var.external_api_token  # Passed at bootstrap time
}

# Grant access to workflow service account
resource "google_secret_manager_secret_iam_member" "external_api_access" {
  secret_id = google_secret_manager_secret.external_api_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}
```

**External API Usage (GitHub Actions):**
```yaml
- name: Call External API with Bearer Token
  run: |
    EXTERNAL_TOKEN=$(gcloud secrets versions access latest --secret="external-api-token")
    
    curl -X POST "https://api.example.com/v1/endpoint" \
      -H "Authorization: Bearer $EXTERNAL_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"data": "..."}' \
      --connect-timeout 5 \
      --max-time 30
```

---

## Provider Decision Matrix

| Provider | Required | Evidence | Cost | Setup Difficulty |
|----------|----------|----------|------|------------------|
| GCP | ✅ Yes | Currently Proven | Free tier available | Medium |
| GitHub | ✅ Yes | Currently Proven | Free with public repos | Low |
| Railway | ⭕ Optional | Historically Proven | ~$5-20/month | Low |
| Cloudflare | ⭕ Optional | Historically Proven | Free tier available | Medium |
| N8N | ⭕ Optional | Historically Proven | Self-hosted or $25+/month | High |
| External APIs | ⭕ Optional | Needs Validation | Varies | Varies |

---

## Disabling Optional Providers

To disable a provider, set in `terraform.tfvars`:

```hcl
enable_railway    = false
enable_cloudflare = false
enable_n8n       = false
```

The template remains fully functional with only GCP + GitHub enabled.

---

**End of Provider Integration Patterns**
