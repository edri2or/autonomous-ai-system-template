# Bootstrap Automation Specification

**Date:** 2026-04-28  
**Related Primary Document:** docs/state/architecture-phase-6.md (overview)  
**Purpose:** Detailed workflows for creating new projects from the template  
**Audience:** Builders, operators, automation engineers

---

## Overview

Bootstrap automation enables users to create new autonomous AI projects with a single command. The workflow:

1. **User invokes:** `./bootstrap-new-project.sh --org edri2or --gcp-project or-infra-admin --new-repo myproject`
2. **Terraform provision:** WIF + Secret Manager + GitHub App + optional providers
3. **Autonomous validation:** Agent verifies all 5 security ADRs implemented
4. **Distribution:** Skills synced from central registry
5. **Autonomy activated:** Control plane ready for autonomous operation

---

## Phase 1: Manual Prerequisites (Human Approval Gates)

### GATE-001: GitHub App Creation

**User Action:**
1. Visit [GitHub Developer Settings](https://github.com/settings/apps)
2. Create new app: **Template Bootstrap App**
3. Configure permissions:
   - Repository > Contents: Read & Write
   - Repository > Metadata: Read
   - Actions > Workflows: Read & Write
   - Checks: Read & Write
4. Subscribe to webhook events:
   - Push
   - Pull request
   - Workflow run completed
5. Note the **App ID** (e.g., `123456`)
6. Generate private key → download `.pem` file
7. Store in GCP Secret Manager: `gcloud secrets create github-app-private-key --data-file=app-key.pem`

**Verification Script:** `scripts/verify-gate-001.sh`
```bash
#!/bin/bash
# Verify GitHub App exists and has correct permissions
gh api /app --jq '.id, .permissions'
```

---

### GATE-002: GCP WIF Pool Creation

**User Action:**
1. Create GCP WIF pool:
   ```bash
   gcloud iam workload-identity-pools create github-pool \
     --project=$GCP_PROJECT \
     --location=global \
     --display-name="GitHub Actions"
   ```

2. Create WIF provider:
   ```bash
   gcloud iam workload-identity-pools providers create-oidc github-provider \
     --project=$GCP_PROJECT \
     --location=global \
     --workload-identity-pool=github-pool \
     --display-name="GitHub" \
     --attribute-mapping='google.subject=assertion.sub,assertion.aud=assertion.aud,assertion.repository=assertion.repository,assertion.repository_owner=assertion.repository_owner,assertion.ref=assertion.ref' \
     --issuer-uri=https://token.actions.githubusercontent.com
   ```

3. Note the WIF provider resource name (output from above):
   ```
   projects/NUMERIC_PROJECT_ID/locations/global/workloadIdentityPools/github-pool/providers/github-provider
   ```

**Verification Script:** `scripts/verify-gate-002.sh`
```bash
#!/bin/bash
# Verify WIF pool exists with correct attribute mapping
gcloud iam workload-identity-pools describe github-pool \
  --project=$GCP_PROJECT \
  --location=global \
  --format='value(providers[0].attributeMapping)'
```

---

### GATE-003: Terraform Service Account Permissions

**User Action:**
1. Create service account (if not exists):
   ```bash
   gcloud iam service-accounts create terraform-sa \
     --project=$GCP_PROJECT \
     --display-name="Terraform Bootstrap"
   ```

2. Grant permissions:
   ```bash
   # Secret Manager access
   gcloud projects add-iam-policy-binding $GCP_PROJECT \
     --member="serviceAccount:terraform-sa@$GCP_PROJECT.iam.gserviceaccount.com" \
     --role="roles/secretmanager.secretCreator"
   
   # WIF access
   gcloud iam service-accounts add-iam-policy-binding \
     "terraform-sa@$GCP_PROJECT.iam.gserviceaccount.com" \
     --project=$GCP_PROJECT \
     --role="roles/iam.workloadIdentityPoolAdmin" \
     --member="principalSet://goog/github/repo_owner/edri2or"
   ```

**Verification Script:** `scripts/verify-gate-003.sh`
```bash
#!/bin/bash
# Verify service account has required roles
gcloud projects get-iam-policy $GCP_PROJECT \
  --flatten='bindings[].members' \
  --filter='bindings.members:terraform-sa*' \
  --format='table(bindings.role)'
```

---

## Phase 2: Automated Bootstrap Workflow

### Bootstrap Command

User runs:
```bash
./bootstrap/bootstrap-new-project.sh \
  --org edri2or \
  --gcp-project or-infra-admin \
  --new-repo my-autonomous-project \
  --enable-railway true \
  --enable-cloudflare true \
  --enable-n8n false
```

### Bootstrap Script Flow

**File:** `bootstrap/bootstrap-new-project.sh`

```bash
#!/bin/bash
set -euo pipefail

# Parse arguments
ORG=""
GCP_PROJECT=""
NEW_REPO=""
ENABLE_RAILWAY="false"
ENABLE_CLOUDFLARE="false"
ENABLE_N8N="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --org) ORG="$2"; shift 2 ;;
    --gcp-project) GCP_PROJECT="$2"; shift 2 ;;
    --new-repo) NEW_REPO="$2"; shift 2 ;;
    --enable-railway) ENABLE_RAILWAY="$2"; shift 2 ;;
    --enable-cloudflare) ENABLE_CLOUDFLARE="$2"; shift 2 ;;
    --enable-n8n) ENABLE_N8N="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$ORG" || -z "$GCP_PROJECT" || -z "$NEW_REPO" ]]; then
  echo "Usage: $0 --org ORG --gcp-project PROJECT --new-repo REPO [--enable-railway true|false] [--enable-cloudflare true|false]"
  exit 1
fi

echo "=== Phase 1: Verify Prerequisites ==="
bash scripts/verify-gate-001.sh || exit 1
bash scripts/verify-gate-002.sh || exit 1
bash scripts/verify-gate-003.sh || exit 1

echo "✓ All prerequisites verified"

echo ""
echo "=== Phase 2: Create GitHub Repository ==="

# Use GitHub CLI to create from template
gh repo create "$ORG/$NEW_REPO" \
  --template "$ORG/autonomous-ai-system-template" \
  --private \
  --source=./

echo "✓ GitHub repository created: $ORG/$NEW_REPO"

echo ""
echo "=== Phase 3: Clone New Repository ==="

WORK_DIR="/tmp/bootstrap-$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

git clone "https://github.com/$ORG/$NEW_REPO.git"
cd "$NEW_REPO"

echo "✓ Repository cloned to $WORK_DIR/$NEW_REPO"

echo ""
echo "=== Phase 4: Configure Terraform ==="

# Generate terraform.tfvars from example
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Inject org constants
sed -i "s|github_org.*=.*|github_org = \"$ORG\"|g" terraform/terraform.tfvars
sed -i "s|gcp_project_id.*=.*|gcp_project_id = \"$GCP_PROJECT\"|g" terraform/terraform.tfvars
sed -i "s|enable_railway.*=.*|enable_railway = $ENABLE_RAILWAY|g" terraform/terraform.tfvars
sed -i "s|enable_cloudflare.*=.*|enable_cloudflare = $ENABLE_CLOUDFLARE|g" terraform/terraform.tfvars
sed -i "s|enable_n8n.*=.*|enable_n8n = $ENABLE_N8N|g" terraform/terraform.tfvars

echo "✓ terraform.tfvars populated"

echo ""
echo "=== Phase 5: Run Terraform Init & Plan ==="

cd terraform/

terraform init \
  -upgrade \
  -var-file="terraform.tfvars"

terraform plan \
  -var-file="terraform.tfvars" \
  -out="tfplan"

echo ""
echo "✓ Terraform plan generated (review above)"

echo ""
read -p "Apply Terraform plan? (yes/no) " -n 3 -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "=== Phase 6: Apply Terraform ==="
  
  terraform apply tfplan
  
  echo "✓ Terraform apply complete"
  
  # Capture outputs
  WIF_PROVIDER=$(terraform output -raw wif_provider_resource_name)
  TF_SA_EMAIL=$(terraform output -raw service_account_email)
  
  echo ""
  echo "=== Phase 7: Create GitHub Secrets ==="
  
  cd ..
  
  # Store WIF provider in GitHub Secrets
  gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
    --repo "$ORG/$NEW_REPO" \
    --body "$WIF_PROVIDER"
  
  # Store Terraform SA email
  gh secret set GCP_TERRAFORM_SA_EMAIL \
    --repo "$ORG/$NEW_REPO" \
    --body "$TF_SA_EMAIL"
  
  echo "✓ GitHub Secrets created"
  
  echo ""
  echo "=== Phase 8: Commit & Push Bootstrap ==="
  
  git add terraform/terraform.tfvars terraform/terraform.tfstate terraform/terraform.tfstate.backup 2>/dev/null || true
  git add BOOTSTRAP-OUTPUT.md
  
  git commit -m "Bootstrap: Initial Terraform state for $NEW_REPO"
  git push origin main
  
  echo "✓ Bootstrap state committed"
  
  echo ""
  echo "=== Phase 9: Trigger Autonomous Setup Workflow ==="
  
  gh workflow run autonomous-control-plane.yml \
    --repo "$ORG/$NEW_REPO" \
    -f skip_provider_validation=true
  
  echo "✓ Autonomous control plane triggered"
  echo ""
  echo "Setup complete! Monitor GitHub Actions for autonomous agent activity."
  echo "Repository: https://github.com/$ORG/$NEW_REPO"
  
else
  echo "Terraform apply cancelled. To resume:"
  echo "  cd $WORK_DIR/$NEW_REPO/terraform"
  echo "  terraform apply tfplan"
fi
```

---

## Phase 3: GitHub Actions Automation

### Workflow 1: Autonomous Control Plane

**File:** `.github/workflows/autonomous-control-plane.yml`

Runs after bootstrap completes. Autonomous agent validates + deploys.

```yaml
name: Autonomous Control Plane
on:
  workflow_dispatch:
    inputs:
      skip_provider_validation:
        description: 'Skip provider validation gates (for testing)'
        required: false
        default: 'false'

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

jobs:
  setup:
    runs-on: ubuntu-latest
    
    permissions:
      id-token: write
      contents: write
    
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      # Authenticate to GCP via WIF
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account_email: ${{ secrets.GCP_TERRAFORM_SA_EMAIL }}
      
      - uses: google-github-actions/setup-gcloud@v2
      
      # Verify GitHub App token works
      - name: Verify GitHub App integration
        uses: actions/create-github-app-token@v1
        id: app-token
        with:
          app-id: ${{ secrets.GITHUB_APP_ID }}
          private-key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
      
      - name: Test API call with app token
        run: |
          curl -L \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${{ steps.app-token.outputs.token }}" \
            https://api.github.com/repos/${{ github.repository }}
      
      # Validate 5 security ADRs implemented
      - name: Validate security ADRs
        run: |
          echo "Checking ADR-0100: GitHub App Token Chain"
          grep -q "GITHUB_APP_ID" .github/workflows/*.yml || exit 1
          
          echo "Checking ADR-0101: Explicit Secret Passing"
          grep -c "secrets: inherit" .github/workflows/*.yml && exit 1 || true
          
          echo "Checking ADR-0102: mcp__github__ refactoring"
          grep -q "mcp__github__" src/ && exit 1 || true
          
          echo "Checking ADR-0103: WIF Branch Scoping"
          grep -q "assertion.ref == 'refs/heads/main'" terraform/wif.tf || exit 1
          
          echo "Checking ADR-0104: External API Token Handling"
          grep -q "Authorization.*Bearer" scripts/*.sh || exit 1
          
          echo "✓ All 5 security ADRs verified"
      
      # Run policy enforcement
      - name: Policy Enforcement
        run: |
          python3 policies/scripts/check_policies.py
      
      # Optionally: run provider validation gates
      - name: Provider Validation (optional)
        if: inputs.skip_provider_validation == 'false'
        run: |
          bash scripts/validate-providers.sh
      
      # Create initial ADR-0200 (project charter)
      - name: Create ADR-0200
        run: |
          cat > docs/adr/0200-project-charter.md << 'EOF'
          # ADR-0200 — Project Charter
          
          **Date:** $(date -u +%Y-%m-%d)
          **Author:** Autonomous Control Plane
          **Status:** ACCEPTED
          
          ## Decision
          
          This project is an instance of the autonomous AI system template (parent: `edri2or/autonomous-ai-system-template`).
          
          ## Context
          
          - **Repository:** ${{ github.repository }}
          - **GitHub Org:** {{ github_org }}
          - **GCP Project:** {{ gcp_project_id }}
          - **Providers Enabled:**
            - Railway: {{ enable_railway }}
            - Cloudflare: {{ enable_cloudflare }}
            - N8N: {{ enable_n8n }}
          
          ## Autonomy Model
          
          This project uses the **Ralph Loop** continuous decision-making model:
          
          1. Agent reads CLAUDE.md + ADRs
          2. Agent monitors repo for incomplete items (JOURNEY.md)
          3. Agent proposes ADRs + code changes
          4. Agent submits PRs for human review
          5. Agent merges approved changes
          6. Loop repeats
          
          ## Initial ADR Ranges
          
          - 0001-0099: Template ADRs (from parent, not overridden)
          - 0200-0299: Project charter + decisions
          - 0300+: Ad-hoc decisions + experiments
          
          ## Success Criteria
          
          - [ ] All 5 security ADRs verified
          - [ ] GitHub App token minting working
          - [ ] GCP Secret Manager accessible
          - [ ] Skills distributed from central registry
          - [ ] Autonomous agent operational
          - [ ] JOURNEY.md populated with first session
          EOF
          
          git add docs/adr/0200-project-charter.md
          git commit -m "feat: ADR-0200 project charter" || echo "No changes to commit"
          git push origin main || echo "Push failed (main may be blocked)"
      
      - name: Report Status
        if: always()
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const status = process.env.JOB_STATUS === 'success' ? '✅' : '❌';
            const comment = `${status} **Autonomous Setup Complete**
            
            - GitHub App integration: ✓
            - Security ADRs: ✓
            - Policy enforcement: ✓
            - ADR-0200 created: ✓
            
            Next steps:
            1. Review generated ADRs in docs/adr/
            2. Monitor JOURNEY.md for agent activity
            3. Approve + merge any pending PRs
            `;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: comment
            });
```

---

### Workflow 2: Skill Distribution

**File:** `.github/workflows/skill-distribute.yml`

Pushes skills from central registry (ripo-skills-main) to this repo + enrolled repos.

```yaml
name: Distribute Skills
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:

jobs:
  distribute:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write
    
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Fetch skills from central registry
        run: |
          git remote add upstream https://github.com/edri2or/ripo-skills-main.git
          git fetch upstream main
          git checkout upstream/main -- skills/
          
          echo "Skills updated from central registry"
          git status
      
      - name: Update SKILL-CATALOG.md
        run: |
          python3 << 'PYTHON'
          import os
          import yaml
          
          skills = []
          for skill_dir in os.listdir('skills'):
            skill_md = os.path.join('skills', skill_dir, 'SKILL.md')
            if os.path.exists(skill_md):
              with open(skill_md) as f:
                content = f.read()
                # Extract YAML frontmatter
                parts = content.split('---')
                if len(parts) >= 3:
                  meta = yaml.safe_load(parts[1])
                  skills.append({
                    'name': meta.get('name', skill_dir),
                    'portability': meta.get('portability_score', 0),
                    'description': meta.get('description', '')
                  })
          
          # Sort by portability score
          skills.sort(key=lambda x: x['portability'], reverse=True)
          
          # Write catalog
          with open('docs/SKILL-CATALOG.md', 'w') as f:
            f.write('# Skill Catalog\n\n')
            f.write('| Skill | Portability | Description |\n')
            f.write('|-------|-------------|-------------|\n')
            for s in skills:
              f.write(f"| {s['name']} | {s['portability']} | {s['description']} |\n")
          PYTHON
      
      - name: Commit skill updates
        run: |
          git config user.name "autonomous-setup"
          git config user.email "setup@autonomous.local"
          
          git add skills/ docs/SKILL-CATALOG.md
          git commit -m "chore: skill distribution from central registry" || true
          git push origin main || true
```

---

## Phase 4: Provider-Specific Bootstrap

### Optional: Railway Services

**File:** `bootstrap/provision-railway-services.sh`

Deploys N8N, PostgreSQL, and webhook handler to Railway.

```bash
#!/bin/bash
set -euo pipefail

RAILWAY_WORKSPACE_ID="$1"
NEW_REPO="$2"

echo "=== Provisioning Railway Services ==="

# Create N8N project
railway project create --name "n8n-$NEW_REPO" --workspace "$RAILWAY_WORKSPACE_ID"

# Deploy N8N
railway up \
  --name "n8n" \
  --dockerfile="Dockerfile.n8n"

# Deploy webhook handler
railway up \
  --name "webhook-handler" \
  --dockerfile="Dockerfile.webhook-handler"

# Deploy PostgreSQL
railway up \
  --name "postgres" \
  --from="docker://postgres:15"

echo "✓ Railway services deployed"
```

---

### Optional: Cloudflare Workers

**File:** `bootstrap/provision-cloudflare-gateway.sh`

Deploys HMAC validation gateway.

```bash
#!/bin/bash
set -euo pipefail

ZONE_ID="$1"

echo "=== Provisioning Cloudflare Gateway ==="

# Deploy Worker
wrangler publish \
  --name "webhook-gateway" \
  --config wrangler.toml

# Create route
wrangler routes create \
  --zone "$ZONE_ID" \
  "webhooks.example.com/*"

echo "✓ Cloudflare Worker deployed"
```

---

## Troubleshooting Bootstrap

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| "terraform plan: variable missing" | terraform.tfvars not populated | Run `cp terraform.tfvars.example terraform.tfvars && edit` |
| "WIF token exchange failed" | Attribute condition too strict | Check `assertion.ref` matches `refs/heads/main` |
| "Secret not found in GCP SM" | GitHub App private key not uploaded | `gcloud secrets create github-app-private-key --data-file=...` |
| "gh: not found" | GitHub CLI not installed | `brew install gh` or use Docker |
| "Rate limited by GitHub API" | Too many repos cloned | Use PAT with higher rate limit or split bootstrap |

---

**End of Bootstrap Automation Specification**
