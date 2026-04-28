# Cloud-Native Bootstrap Guide

**No local machine required.** This guide covers two paths for deploying a new autonomous project
entirely from a browser, without installing anything locally.

---

## Choose Your Path

| Path | Best for | Time | GCP auth |
|------|----------|------|----------|
| [A: GitHub Actions workflow](#path-a-github-actions-workflow) | Repeatable, auditable deploys | ~10 min setup | Temporary SA key |
| [B: GCP Cloud Shell](#path-b-gcp-cloud-shell) | First-time setup, debugging | ~5 min setup | Pre-authenticated |

---

## Prerequisites (both paths)

Before starting either path, complete the manual gates in [`docs/gates/manual-gates.md`](../gates/manual-gates.md).

Required:
- [ ] **GATE-001:** GitHub App created, private key stored in GCP Secret Manager
- [ ] GCP project exists with billing enabled
- [ ] This template repository is accessible (the repo you're reading now)

Optional (enable only what you need):
- [ ] **GATE-004:** Telegram bot token (if using Telegram integration)
- [ ] **GATE-005:** Railway API token (if `enable_railway = true`)
- [ ] **GATE-006:** Cloudflare API token (if `enable_cloudflare = true`)

---

## Path A: GitHub Actions Workflow

This path runs bootstrap as a GitHub Actions job — no terminal needed at all.

### Step 1 — Create a GCP Bootstrap Service Account

This is the **only** GCP service account key you'll ever create. It's used once for bootstrap,
then deleted once WIF is working.

1. Go to [GCP Console → IAM → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. **Create Service Account**: name `bootstrap-sa`
3. Grant these roles:
   - `roles/secretmanager.admin`
   - `roles/iam.workloadIdentityPoolAdmin`
   - `roles/resourcemanager.projectIamAdmin`
   - `roles/iam.serviceAccountAdmin`
4. Click **Done**
5. Click the service account → **Keys** tab → **Add Key** → **Create new key** → JSON → **Create**
6. The JSON key file downloads to your browser

### Step 2 — Add GitHub Secrets

In this template repository → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret name | Value |
|------------|-------|
| `GCP_BOOTSTRAP_SA_KEY` | Full contents of the JSON key file downloaded above |
| `GH_BOOTSTRAP_PAT` | A GitHub Classic PAT with scopes: `repo`, `workflow`, `admin:org` (create at https://github.com/settings/tokens) |

### Step 3 — Trigger the Bootstrap Workflow

1. Go to this repository → **Actions** tab
2. Select **Bootstrap New Project** workflow
3. Click **Run workflow** and fill in:
   - `new_repo`: name for your new project (e.g., `my-autonomous-project`)
   - `gcp_project`: your GCP project ID
   - `enable_railway` / `enable_cloudflare` / `enable_n8n`: `true` or `false`
   - `apply`: **leave unchecked for a dry-run** (Terraform plan only) — check to actually apply
4. Click **Run workflow**

### Step 4 — Review the Plan, Then Apply

1. After the dry-run succeeds, review the Terraform plan output in the workflow logs
2. Run workflow again with **apply** checked to execute

### Step 5 — Verify and Clean Up

1. Monitor the new repo's Actions: `https://github.com/YOUR_ORG/YOUR_NEW_REPO/actions`
2. Confirm `autonomous-control-plane.yml` passes all checks
3. Confirm `docs/adr/0200-project-charter.md` was created
4. **Delete** `GCP_BOOTSTRAP_SA_KEY` from GitHub Secrets — WIF is now active, SA key no longer needed

---

## Path B: GCP Cloud Shell

GCP Cloud Shell is a browser-based terminal at https://shell.cloud.google.com.
It is pre-authenticated to your GCP project and has `gcloud` and `git` installed.

### Step 1 — Open Cloud Shell

Go to https://shell.cloud.google.com (or click the `>_` icon in GCP Console).

### Step 2 — Install Terraform

```bash
# One-time install in Cloud Shell (pinned to match the bootstrap workflow):
TF_VERSION="1.9.0"
wget -qO terraform.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
unzip -q terraform.zip && sudo mv terraform /usr/local/bin/ && rm terraform.zip
terraform version
```

### Step 3 — Clone This Template

```bash
export GH_TOKEN="YOUR_GITHUB_PAT"
git clone "https://x-access-token:${GH_TOKEN}@github.com/edri2or/autonomous-ai-system-template.git"
cd autonomous-ai-system-template
```

### Step 4 — Run Manual Gates (if not already done)

Cloud Shell is pre-authenticated to your GCP project — just confirm:
```bash
gcloud auth list
gcloud config set project YOUR_GCP_PROJECT
```

Run gate verification:
```bash
bash scripts/verify-gate-001.sh YOUR_GCP_PROJECT
bash scripts/verify-gate-002.sh YOUR_GCP_PROJECT  # Optional — Terraform can create WIF
bash scripts/verify-gate-003.sh YOUR_GCP_PROJECT  # Optional — Terraform can create SA
```

### Step 5 — Run Bootstrap (Dry Run First)

```bash
export GH_TOKEN="YOUR_GITHUB_PAT"

# Dry run — Terraform plan only (no --yes flag):
bash bootstrap/bootstrap-new-project.sh \
  --org YOUR_ORG \
  --gcp-project YOUR_GCP_PROJECT \
  --new-repo my-autonomous-project \
  --enable-railway false \
  --enable-cloudflare false
```

Review the Terraform plan output.

### Step 6 — Apply Bootstrap

```bash
# Apply — add --yes to skip interactive prompt:
bash bootstrap/bootstrap-new-project.sh \
  --org YOUR_ORG \
  --gcp-project YOUR_GCP_PROJECT \
  --new-repo my-autonomous-project \
  --enable-railway false \
  --enable-cloudflare false \
  --yes
```

### Step 7 — Verify

1. Monitor the new repo's Actions: `https://github.com/YOUR_ORG/my-autonomous-project/actions`
2. Confirm `autonomous-control-plane.yml` passes
3. Confirm `docs/adr/0200-project-charter.md` was created

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `GATE-001 FAIL: secret not found` | Private key not stored in GCP SM | Follow GATE-001 steps in `docs/gates/manual-gates.md` |
| `WIF token exchange failed` | Attribute condition wrong | Check `assertion.ref == 'refs/heads/main'` in `terraform/wif.tf` |
| `terraform: command not found` (Cloud Shell) | Terraform not installed | Follow Step 2 above |
| `GH_TOKEN: not set` | PAT missing | `export GH_TOKEN="YOUR_PAT"` |
| `403 on GitHub secrets API` | PAT missing `admin:org` scope | Recreate PAT with correct scopes |
| GitHub Actions auth fails after bootstrap | WIF attribute condition too strict | Verify WIF condition matches repo + main branch |

---

## After Bootstrap

Once the new project is running:

1. The `autonomous-control-plane.yml` workflow runs on every push to `main`
2. ADRs 0100–0104 are validated automatically
3. Skills are synced daily from the central registry (`ripo-skills-main`)
4. The agent operates autonomously, proposing PRs for human review

Your project is ready for autonomous operation.
