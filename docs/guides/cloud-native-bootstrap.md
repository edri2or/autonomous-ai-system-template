# Cloud-Native Bootstrap Guide

**No local machine required.** Bootstrap a new autonomous project entirely from a browser using
GCP Cloud Shell — no local installs, no SA keys, no manual secret configuration.

---

## Recommended Path: GCP Cloud Shell + pre-bootstrap.sh

This is the single supported bootstrap path. It runs entirely from the GCP Cloud Shell browser
terminal and requires **zero manual secret configuration**.

### User actions (the only manual steps allowed):

| Step | Action |
|------|--------|
| 1 | Open [GCP Cloud Shell](https://shell.cloud.google.com) |
| 2 | Clone this repo and run `pre-bootstrap.sh` (one command) |
| 3 | Open the GitHub URL shown and click "Create GitHub App" |
| 4 | Click "Install App" on GitHub (one additional click after app is created) |
| 5 | Confirm Terraform apply |

Everything else — App credentials, WIF provisioning, GitHub secrets, workflow trigger — is automated.

---

## Step-by-step

### Step 1 — Open GCP Cloud Shell

Go to [https://shell.cloud.google.com](https://shell.cloud.google.com) (or click the `>_` icon
in the GCP Console header).

Cloud Shell is pre-authenticated to your GCP project — no `gcloud auth` needed.

### Step 2 — Clone and run pre-bootstrap.sh

```bash
export GH_TOKEN="ghp_..."   # Classic PAT: repo, workflow, admin:org

git clone https://github.com/edri2or/autonomous-ai-system-template.git
cd autonomous-ai-system-template

bash bootstrap/pre-bootstrap.sh \
  --gcp-project  YOUR_GCP_PROJECT_ID \
  --org          YOUR_GITHUB_ORG \
  --new-repo     your-new-project-name
```

Optional flags:
- `--enable-railway true` — provision Railway integration
- `--enable-cloudflare true` — provision Cloudflare integration
- `--yes` — skip the Terraform confirmation prompt in Step 5

### Step 3 — Create GitHub App (one click)

The script prints a URL. Open it in your browser and click **"Create GitHub App"**.

The script starts an HTTP server on port 8080 in Cloud Shell. Cloud Shell exposes this port via
a public preview URL (`https://8080-${WEB_HOST}/callback`, where `WEB_HOST` is a Cloud Shell
environment variable containing your session's domain). When GitHub redirects back after you
click "Create", the HTTP server catches the callback code automatically — **you do not need
to copy or paste any URL**.

The script converts the code into App credentials, stores the App ID and private key in
**GCP Secret Manager** automatically, and shreds the local copy. You will never handle
the `.pem` file directly.

### Step 4 — Install App (one click)

After GitHub creates the app, it shows an **"Install App"** button on the same page.
Click it and confirm the installation for your organization. This grants the app access
to your repositories.

Return to Cloud Shell — the script continues automatically.

### Step 5 — Confirm Terraform apply

Review the plan output and type `y` to apply. Terraform creates:
- GCP Workload Identity Pool + Provider (keyless GitHub → GCP auth)
- Service Account with least-privilege IAM bindings
- Secret Manager access for GitHub App credentials

After apply, the script sets `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT_EMAIL`
as GitHub secrets in the new repo.

### Done

The script triggers `autonomous-control-plane.yml` in the new repo and prints the Actions URL.
Monitor the workflow run to confirm all ADR checks pass and `docs/adr/0200-project-charter.md`
is created.

---

## Advanced: Re-run via GitHub Actions

After `pre-bootstrap.sh` has provisioned WIF, you can re-run bootstrap steps from the GitHub
Actions UI using the **Bootstrap New Project** workflow
(`.github/workflows/bootstrap-new-project.yml`).

This workflow uses WIF for GCP auth (no SA key). It also requires `GH_PAT` as a repo secret
(set via API — see `bootstrap/bootstrap-new-project.sh` for the `set_github_secret` helper).

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `GATE-001 FAIL: secret not found` | App key not stored in GCP SM | Re-run `pre-bootstrap.sh` from step 1 |
| `WIF token exchange failed` | Attribute condition wrong | Check `assertion.ref == 'refs/heads/main'` in `terraform/wif.tf` |
| `terraform: command not found` | Not installed | Script installs Terraform automatically |
| `GH_TOKEN: not set` | PAT missing | `export GH_TOKEN="YOUR_PAT"` |
| `ERROR: WEB_HOST not set` | Not running in Cloud Shell | Script must run from [shell.cloud.google.com](https://shell.cloud.google.com) |
| `No code received from GitHub (timeout)` | App not created in time | Re-run; click "Create GitHub App" within the 120-second window shown |
| `ERROR: Failed to get App ID` | Manifest code expired | Re-run; codes expire after 1 hour — complete the flow promptly |

---

## After Bootstrap

Once the new project is running:

1. `autonomous-control-plane.yml` runs on every push to `main`
2. ADRs 0100–0104 are validated automatically
3. Skills are synced daily from the central registry (`ripo-skills-main`)
4. The agent operates autonomously, proposing PRs for human review

Your project is ready for autonomous operation.
