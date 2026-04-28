# Manual Bootstrap Gates

This document describes all manual human actions required before running the automated bootstrap.
Each gate has a corresponding verification script in `scripts/`.

---

## Execution Environments — No Local Machine Required

All gates can be completed using **browser-only tools**. There are two paths:

| Path | When to use | Tools |
|------|-------------|-------|
| **A: GCP Cloud Shell** | Preferred — authenticated to GCP automatically | Browser terminal at https://shell.cloud.google.com |
| **B: GCP Console + GitHub Actions** | Fully web-UI driven | GCP Console web UI + GitHub web UI |

**GCP Cloud Shell** is a browser-based terminal pre-authenticated to your GCP project.
It has `gcloud` and `git` pre-installed. `terraform` can be installed in one command (see below).
Open it at: https://shell.cloud.google.com

All `gcloud` commands in this document work identically in Cloud Shell and locally.

---

## GATE-001: GitHub App Creation

**Status:** Manual (GitHub web UI required)
**Verified by:** `scripts/verify-gate-001.sh`

### Step 1 — Create the GitHub App (GitHub web UI)

1. Go to **GitHub Developer Settings → GitHub Apps → New GitHub App**
   - URL: `https://github.com/organizations/YOUR_ORG/settings/apps/new`
   - (Personal accounts: `https://github.com/settings/apps/new`)

2. Configure the app:
   - **Name:** `YOUR_ORG-autonomous-bootstrap`
   - **Homepage URL:** `https://github.com/YOUR_ORG`
   - **Webhook:** Disabled
   - **Repository permissions:**
     - Contents: Read & Write
     - Metadata: Read
     - Actions: Read & Write
     - Checks: Read & Write
     - Pull requests: Read & Write
     - Issues: Read & Write
   - **Where can this app be installed?** Only this account

3. Click **Create GitHub App**

4. Note the **App ID** (shown at the top of the app settings page, e.g., `123456`)

5. Scroll to **Private keys** → **Generate a private key** → a `.pem` file downloads to your browser

### Step 2 — Store the private key in GCP Secret Manager

**Option A — GCP Cloud Shell:**
```bash
# Upload the .pem file to Cloud Shell first (Cloud Shell menu → Upload)
gcloud secrets create github-app-private-key \
  --replication-policy=automatic \
  --data-file=app-key.pem \
  --project=YOUR_GCP_PROJECT

# Store the App ID
echo -n "123456" | gcloud secrets versions add github-app-id \
  --data-file=- \
  --project=YOUR_GCP_PROJECT
```

**Option B — GCP Console web UI (no terminal needed):**
1. Go to [GCP Console → Secret Manager](https://console.cloud.google.com/security/secret-manager)
2. Click **Create Secret**
   - Name: `github-app-private-key`
   - Secret value: paste the contents of the `.pem` file
   - Click **Create Secret**
3. Repeat for `github-app-id`: secret value = your App ID number (e.g., `123456`)

### Step 3 — Delete the local .pem file

The key is now in Secret Manager. Delete the downloaded `.pem` file from your browser's Downloads folder.

### Step 4 — Install the app

Go to the app settings → **Install App** → select org → select repository (or all repositories).

### Verification

```bash
# Run in GCP Cloud Shell:
bash scripts/verify-gate-001.sh YOUR_GCP_PROJECT
```

---

## GATE-002: GCP WIF Pool and Provider

**Status:** Manual (gcloud CLI required, or automated by Terraform)
**Verified by:** `scripts/verify-gate-002.sh`

> **Note:** If you plan to let Terraform create the WIF pool during bootstrap, skip this gate.
> Terraform handles GATE-002 automatically on first apply.

**Option A — GCP Cloud Shell:**
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

**Option B — GCP Console web UI:**
1. Go to [IAM & Admin → Workload Identity Federation](https://console.cloud.google.com/iam-admin/workload-identity-pools)
2. Click **Create Pool** → name: `github-pool` → Continue
3. Add Provider → **OpenID Connect (OIDC)**
   - Provider name: `github-provider`
   - Issuer URL: `https://token.actions.githubusercontent.com`
4. Configure attribute mapping:
   - `google.subject` = `assertion.sub`
   - `assertion.repository` = `assertion.repository`
   - `assertion.ref` = `assertion.ref`
5. Add attribute condition:
   ```
   assertion.repository == 'YOUR_ORG/YOUR_REPO' && assertion.ref == 'refs/heads/main'
   ```

### Verification

```bash
# Run in GCP Cloud Shell:
bash scripts/verify-gate-002.sh YOUR_GCP_PROJECT
```

---

## GATE-003: Terraform Service Account

**Status:** Manual (gcloud CLI required, or automated by Terraform)
**Verified by:** `scripts/verify-gate-003.sh`

> **Note:** Terraform creates and configures the service account automatically.
> Only run this gate manually if you need to verify permissions before applying.

**Option A — GCP Cloud Shell:**
```bash
gcloud iam service-accounts create terraform-bootstrap \
  --project=YOUR_GCP_PROJECT \
  --display-name="Terraform Bootstrap"

gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT \
  --member="serviceAccount:terraform-bootstrap@YOUR_GCP_PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Option B — GCP Console web UI:**
1. Go to [IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Click **Create Service Account**
   - Name: `terraform-bootstrap`
   - Click **Create and Continue**
3. Add role: **Secret Manager Secret Accessor**
4. Click **Done**

### Verification

```bash
# Run in GCP Cloud Shell:
bash scripts/verify-gate-003.sh YOUR_GCP_PROJECT
```

---

## GATE-004: Telegram Bot (Optional)

**Status:** Manual (BotFather required, only if using Telegram integration)

1. Open Telegram → message **@BotFather** → send `/newbot`
2. Choose a name and username → BotFather returns a token like `123456789:ABCDef...`

**Store in GCP Secret Manager:**

Option A — Cloud Shell:
```bash
echo -n "YOUR_BOT_TOKEN" | gcloud secrets versions add telegram-bot-token \
  --data-file=- \
  --project=YOUR_GCP_PROJECT
```

Option B — GCP Console: Secret Manager → `telegram-bot-token` → Add Version → paste token

---

## GATE-005: Railway API Token (Optional)

**Status:** Manual (Railway dashboard, only if `enable_railway = true`)

1. Go to [Railway → Account → Tokens](https://railway.app/account/tokens)
2. Create a new token with workspace scope

**Store in GCP Secret Manager:**

Option A — Cloud Shell:
```bash
echo -n "YOUR_RAILWAY_TOKEN" | gcloud secrets versions add railway-api-token \
  --data-file=- \
  --project=YOUR_GCP_PROJECT
```

Option B — GCP Console: Secret Manager → `railway-api-token` → Add Version → paste token

---

## GATE-006: Cloudflare API Token (Optional)

**Status:** Manual (Cloudflare dashboard, only if `enable_cloudflare = true`)

1. Go to [Cloudflare → Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create token with:
   - **Account → Workers Scripts**: Edit
   - **Zone → Workers Routes**: Edit (for your zone)

**Store in GCP Secret Manager:**

Option A — Cloud Shell:
```bash
echo -n "YOUR_CF_TOKEN" | gcloud secrets versions add cloudflare-api-token \
  --data-file=- \
  --project=YOUR_GCP_PROJECT
```

Option B — GCP Console: Secret Manager → `cloudflare-api-token` → Add Version → paste token

---

## Gate Checklist (Bootstrap Readiness)

Before running bootstrap:

| Gate | Required | Cloud Shell | Console UI | Status |
|------|----------|-------------|------------|--------|
| GATE-001: GitHub App + key in GCP SM | ✅ Always | ✅ | ✅ | [ ] |
| GATE-002: GCP WIF pool | ✅ Always (or Terraform) | ✅ | ✅ | [ ] |
| GATE-003: Terraform service account | ✅ Always (or Terraform) | ✅ | ✅ | [ ] |
| GATE-004: Telegram bot token | ⭕ If using Telegram | ✅ | ✅ | [ ] |
| GATE-005: Railway API token | ⭕ If enable_railway | ✅ | ✅ | [ ] |
| GATE-006: Cloudflare API token | ⭕ If enable_cloudflare | ✅ | ✅ | [ ] |

**Verify in Cloud Shell:**
```bash
bash scripts/verify-gate-001.sh YOUR_GCP_PROJECT
bash scripts/verify-gate-002.sh YOUR_GCP_PROJECT
bash scripts/verify-gate-003.sh YOUR_GCP_PROJECT
```

---

## Running Bootstrap

After all required gates pass, choose your bootstrap method:

- **No machine → GitHub Actions workflow:** See [`.github/workflows/bootstrap-new-project.yml`](../.github/workflows/bootstrap-new-project.yml) — trigger via GitHub web UI → Actions → Bootstrap New Project → Run workflow
- **GCP Cloud Shell:** See [`docs/guides/cloud-native-bootstrap.md`](../guides/cloud-native-bootstrap.md)
