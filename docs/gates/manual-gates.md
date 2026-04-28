# Manual Bootstrap Gates

This document describes all manual human actions required before running the automated bootstrap.
Each gate has a corresponding verification script in `scripts/`.

---

## GATE-001: GitHub App Creation

**Status:** Manual (GitHub UI required)  
**Verified by:** `scripts/verify-gate-001.sh`

### Steps

1. Go to **GitHub Developer Settings → GitHub Apps → New GitHub App**
   - URL: https://github.com/organizations/YOUR_ORG/settings/apps/new

2. Configure the app:
   - **Name:** `YOUR_ORG-autonomous-bootstrap`
   - **Homepage URL:** `https://github.com/YOUR_ORG`
   - **Webhook:** Disabled (or set to your webhook endpoint)
   - **Repository permissions:**
     - Contents: Read & Write
     - Metadata: Read
     - Actions: Read & Write
     - Checks: Read & Write
     - Pull requests: Read & Write
     - Issues: Read & Write
   - **Where can this app be installed?** Only this account

3. Click **Create GitHub App**

4. Note the **App ID** (shown on the app settings page, e.g., `123456`)

5. Scroll to **Private keys** → **Generate a private key** → download `.pem` file

6. Store in GCP Secret Manager:
   ```bash
   gcloud secrets create github-app-private-key \
     --replication-policy=automatic \
     --data-file=app-key.pem \
     --project=YOUR_GCP_PROJECT

   echo -n "123456" | gcloud secrets versions add github-app-id \
     --data-file=- \
     --project=YOUR_GCP_PROJECT
   ```
   (create `github-app-id` secret first if it doesn't exist)

7. **Delete the local .pem file** — it is now in Secret Manager:
   ```bash
   rm app-key.pem
   ```

8. Install the app on the target repository:
   - Go to the app settings → Install App → select org → select repository

### Verification
```bash
bash scripts/verify-gate-001.sh YOUR_GCP_PROJECT
```

---

## GATE-002: GCP WIF Pool and Provider

**Status:** Manual (gcloud CLI required) OR automated by Terraform  
**Verified by:** `scripts/verify-gate-002.sh`

The WIF pool and provider can be created manually OR by Terraform during bootstrap.
If running Terraform for the first time, skip this gate — Terraform creates them.

If you need to pre-create them (e.g., to verify permissions first):

```bash
gcloud iam workload-identity-pools create github-pool \
  --project=YOUR_GCP_PROJECT \
  --location=global \
  --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=YOUR_GCP_PROJECT \
  --location=global \
  --workload-identity-pool=github-pool \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="google.subject=assertion.sub,assertion.repository=assertion.repository,assertion.ref=assertion.ref" \
  --attribute-condition="assertion.repository == 'YOUR_ORG/YOUR_REPO' && assertion.ref == 'refs/heads/main'"
```

### Verification
```bash
bash scripts/verify-gate-002.sh YOUR_GCP_PROJECT
```

---

## GATE-003: Terraform Service Account

**Status:** Manual (gcloud CLI required) OR automated by Terraform  
**Verified by:** `scripts/verify-gate-003.sh`

The service account can be created manually OR by Terraform (recommended — Terraform handles all IAM bindings).

To pre-create manually:
```bash
gcloud iam service-accounts create terraform-bootstrap \
  --project=YOUR_GCP_PROJECT \
  --display-name="Terraform Bootstrap"

gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT \
  --member="serviceAccount:terraform-bootstrap@YOUR_GCP_PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Verification
```bash
bash scripts/verify-gate-003.sh YOUR_GCP_PROJECT
```

---

## GATE-004: Telegram Bot (Optional)

**Status:** Manual (BotFather required, only if using Telegram integration)

1. Open Telegram and message **@BotFather**
2. Send `/newbot`
3. Choose a name and username for your bot
4. BotFather returns a token like `123456789:ABCDefGhIJklmnoPQRsTUVwxYZ`
5. Store in GCP Secret Manager:
   ```bash
   echo -n "YOUR_BOT_TOKEN" | gcloud secrets versions add telegram-bot-token \
     --data-file=- \
     --project=YOUR_GCP_PROJECT
   ```

---

## GATE-005: Railway API Token (Optional)

**Status:** Manual (Railway dashboard required, only if `enable_railway = true`)

1. Log in to Railway: https://railway.app/account/tokens
2. Create a new token with workspace scope
3. Store in GCP Secret Manager:
   ```bash
   echo -n "YOUR_RAILWAY_TOKEN" | gcloud secrets versions add railway-api-token \
     --data-file=- \
     --project=YOUR_GCP_PROJECT
   ```

---

## GATE-006: Cloudflare API Token (Optional)

**Status:** Manual (Cloudflare dashboard required, only if `enable_cloudflare = true`)

1. Log in to Cloudflare: https://dash.cloudflare.com/profile/api-tokens
2. Create a token with permissions:
   - **Account → Workers Scripts**: Edit
   - **Zone → Workers Routes**: Edit (for your target zone)
3. Store in GCP Secret Manager:
   ```bash
   echo -n "YOUR_CF_TOKEN" | gcloud secrets versions add cloudflare-api-token \
     --data-file=- \
     --project=YOUR_GCP_PROJECT
   ```

---

## Gate Checklist (Bootstrap Readiness)

Before running `bootstrap/bootstrap-new-project.sh`:

| Gate | Required | Status |
|------|----------|--------|
| GATE-001: GitHub App + private key in GCP SM | ✅ Always | [ ] |
| GATE-002: GCP WIF pool (or Terraform will create) | ✅ Always | [ ] |
| GATE-003: Terraform service account (or Terraform will create) | ✅ Always | [ ] |
| GATE-004: Telegram bot token | ⭕ If using Telegram | [ ] |
| GATE-005: Railway API token | ⭕ If enable_railway | [ ] |
| GATE-006: Cloudflare API token | ⭕ If enable_cloudflare | [ ] |

Run verification:
```bash
bash scripts/verify-gate-001.sh YOUR_GCP_PROJECT
bash scripts/verify-gate-002.sh YOUR_GCP_PROJECT
bash scripts/verify-gate-003.sh YOUR_GCP_PROJECT
```
