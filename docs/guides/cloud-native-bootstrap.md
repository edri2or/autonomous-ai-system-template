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
| 4 | Paste back the redirect URL |
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
- `--yes` — skip Terraform confirmation prompt (fully non-interactive)

### Step 3 — Create GitHub App (one click)

The script prints a URL. Open it in your browser and click **"Create GitHub App"**.

GitHub redirects you to a URL containing `?code=XXXXXXXXXX`. Copy the full URL from your
browser's address bar and paste it back into the Cloud Shell prompt.

The script stores the App ID and private key in **GCP Secret Manager** automatically and shreds
the local copy. You will never handle the `.pem` file directly.

### Step 4 — Confirm Terraform apply

Review the plan output and type `y` to apply. Terraform creates:
- GCP Workload Identity Pool + Provider (keyless GitHub → GCP auth)
- Service Account with least-privilege IAM bindings
- Secret Manager access for GitHub App credentials

After apply, the script sets `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT_EMAIL`
as GitHub secrets in the new repo — via the GitHub API, not manually.

### Step 5 — Done

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
| `No code= found in URL` | Wrong URL pasted | Ensure you paste the full redirect URL including `?code=...` |
| `ERROR: Failed to get App ID` | Manifest code expired | Re-run; codes expire after ~10 minutes |

---

## After Bootstrap

Once the new project is running:

1. `autonomous-control-plane.yml` runs on every push to `main`
2. ADRs 0100–0104 are validated automatically
3. Skills are synced daily from the central registry (`ripo-skills-main`)
4. The agent operates autonomously, proposing PRs for human review

Your project is ready for autonomous operation.
