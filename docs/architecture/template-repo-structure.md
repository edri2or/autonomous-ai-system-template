# Template Repository Structure Specification

**Date:** 2026-04-28  
**Related Primary Document:** docs/state/architecture-phase-6.md (overview)  
**Purpose:** Detailed directory layout, file purposes, and initialization process  
**Audience:** Builders, infrastructure engineers, template creators

---

## Overview

The final template repository is structured as a **scaffold for bootstrapping autonomous AI systems**. It includes:
- Terraform IaC for GCP infrastructure
- GitHub Actions workflows for security + automation
- Skills router code (proven from all 7 source repos)
- 70+ reusable skills with portability scoring
- Example projects demonstrating 3 generations of architecture
- Comprehensive operations documentation

---

## Directory Structure (Complete)

```
autonomous-ai-system-template/
│
├── README.md                                   # Project overview + quick start
├── BOOTSTRAP.md                                # How to use this template
├── CLAUDE.md                                   # Hot memory rules (template context)
├── JOURNEY.md                                  # Session audit trail (starts empty)
├── LICENSE                                     # MIT or org-chosen license
├── .gitignore                                  # Ignore: .env, *.tfstate*, node_modules/
├── .editorconfig                               # Consistent formatting (tabs/spaces)
│
├── terraform/                                  # IaC for bootstrapping new projects
│   ├── README.md                               # Terraform quick reference
│   ├── main.tf                                 # Root module (org constants injected)
│   ├── wif.tf                                  # GCP WIF pool + provider + attribute condition
│   ├── secrets.tf                              # GCP Secret Manager secret creation
│   ├── github-secrets.tf                       # GitHub Secrets (WIF provider, SA email)
│   ├── github-app.tf                           # GitHub App resource + installation
│   ├── github-org-constants.tf                 # Org-wide constants (org ID, TF SA email)
│   ├── variables.tf                            # Input variables (github_org, gcp_project, etc.)
│   ├── outputs.tf                              # Exported values (WIF pool name, secret names)
│   ├── terraform.tfvars.example                # Example tfvars (rename & populate to use)
│   ├── versions.tf                             # Required Terraform + provider versions
│   ├── .terraformignore                        # Ignore .terraform/ local state
│   │
│   └── modules/                                # Optional provider modules
│       ├── railway-services/                   # (Optional) Railway PaaS deployment
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── nixpacks.toml                   # Nixpacks configuration for Python
│       ├── cloudflare-gateway/                 # (Optional) Cloudflare Workers + routing
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── webhook-gateway.js              # HMAC validation + forwarding
│       └── n8n-workflows/                      # (Optional) N8N automation engine
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── workflow-templates/
│               ├── multi-agent-router.json
│               ├── code-agent-workflow.json
│               ├── infra-agent-workflow.json
│               └── ops-agent-workflow.json
│
├── .github/                                    # GitHub Actions + repository config
│   ├── workflows/                              # CI/CD automation
│   │   ├── documentation-enforcement.yml       # OPA/Python policy validation
│   │   ├── skill-distribute.yml                # Multi-repo skill sync
│   │   ├── skill-contribute.yml                # Upstream skill contribution
│   │   ├── autonomous-control-plane.yml        # Autonomous agent orchestration
│   │   ├── bootstrap-new-project.yml           # Create new project from template
│   │   ├── provider-validation.yml             # Phase 7-9: live provider validation
│   │   └── security-audit.yml                  # Regular security audits
│   │
│   ├── CODEOWNERS                              # Enforce PR reviews for critical paths
│   └── dependabot.yml                          # Automated dependency updates
│
├── policies/                                   # Security enforcement (OPA + Python)
│   ├── README.md                               # Policy enforcement quick reference
│   ├── cli.rego                                # OPA rules: CLI tool restrictions
│   ├── workflows.rego                          # OPA rules: GitHub Actions constraints
│   ├── secrets.rego                            # OPA rules: Credential handling
│   │
│   └── scripts/
│       ├── check_policies.py                   # Python mirror (zero-dependency)
│       ├── test_policies.sh                    # Test harness (sample violations)
│       └── README.md                           # Policy testing guide
│
├── src/                                        # Template code (TypeScript)
│   ├── tsconfig.json                           # TypeScript configuration
│   ├── package.json                            # Dependencies (only dev-time)
│   │
│   ├── agent/                                  # Skills router + core orchestration
│   │   ├── index.ts                            # Main router (from project-life-130)
│   │   ├── router.ts                           # Skill discovery + Jaccard similarity
│   │   ├── types.ts                            # SkillManifest, RouteIntent interfaces
│   │   └── plugins/                            # Built-in plugins (examples)
│   │       ├── gcp-secret-rotate.ts
│   │       ├── github-app-mint.ts
│   │       └── audit-security-policy.ts
│   │
│   ├── utils/                                  # Utility modules
│   │   ├── gcp-client.ts                       # GCP Secret Manager client (curl-based)
│   │   ├── github-client.ts                    # GitHub API client (curl-based, no mcp__)
│   │   ├── terraform-vars.ts                   # Org constants injection
│   │   └── logger.ts                           # Structured logging (for JOURNEY.md)
│   │
│   ├── mcp/                                    # Optional: MCP servers
│   │   ├── admin-server.ts                     # Admin MCP server (from claude-admin)
│   │   └── skill-server.ts                     # Skill metadata server
│   │
│   └── __tests__/                              # Unit tests (Jest)
│       ├── agent.spec.ts
│       ├── router.spec.ts
│       └── gcp-client.spec.ts
│
├── scripts/                                    # Utility scripts (bash/Python)
│   ├── bootstrap-new-org.sh                    # Create GitHub org + repos
│   ├── bootstrap-new-project.sh                # Main bootstrap script (calls terraform)
│   ├── migrate-classic-pat.sh                  # Migrate old repos: PAT → GitHub App
│   ├── provision-gcp-wif.sh                    # Bootstrap WIF pool (idempotent)
│   ├── distribute-skills.sh                    # Sync skills to enrolled repos
│   ├── validate-providers.sh                   # Phase 7-9: run provider validation gates
│   ├── rotate-external-tokens.sh               # Weekly: rotate Railway/Cloudflare tokens
│   └── cleanup-abandoned-projects.sh           # Decommission projects + revoke secrets
│
├── skills/                                     # Reusable skills (70+ total)
│   ├── README.md                               # Skills index + portability guide
│   │
│   ├── gcp-secret-rotate/
│   │   ├── SKILL.md                            # Skill metadata + frontmatter
│   │   ├── script.sh                           # Implementation
│   │   ├── test.sh                             # Test harness
│   │   └── README.md                           # Usage guide
│   │
│   ├── github-app-mint/
│   │   ├── SKILL.md
│   │   ├── script.sh
│   │   └── README.md
│   │
│   ├── audit-security-policy/
│   │   ├── SKILL.md
│   │   ├── audit.py
│   │   └── README.md
│   │
│   ├── distribute-skills/
│   │   ├── SKILL.md
│   │   └── script.sh
│   │
│   ├── create-cloudflare-token/
│   │   ├── SKILL.md
│   │   └── script.sh
│   │
│   ├── auto-subscribe-pr-hook/
│   │   ├── SKILL.md
│   │   └── setup.sh
│   │
│   └── ... (65+ additional skills from ripo-skills-main, adapted)
│
├── examples/                                   # Reference implementations
│   ├── README.md                               # How to use examples
│   │
│   ├── project-life-gen1/                      # Single-repo autonomy (Generation 1)
│   │   ├── README.md                           # Project overview
│   │   ├── CLAUDE.md                           # Project-specific rules
│   │   ├── JOURNEY.md                          # Session audit trail (with entries)
│   │   ├── ARCHITECTURE.md                     # Architecture decisions (links to ADRs)
│   │   ├── BUILD-STAGES.md                     # 8-stage build pipeline description
│   │   ├── .github/workflows/                  # Stage-0 through Stage-7 workflows
│   │   ├── src/                                # Skills router + 40+ skills
│   │   ├── terraform/                          # WIF + Secret Manager + GitHub App
│   │   ├── policies/                           # OPA + Python enforcement
│   │   └── docs/
│   │       ├── ADR/                            # 43 ADRs (0001-0043)
│   │       └── SKILL-CATALOG.md                # Skill descriptions + portability scores
│   │
│   ├── multi-repo-orchestration/               # Multi-repo with 70+ enrolled (Generation 2)
│   │   ├── README.md                           # Project overview
│   │   ├── CLAUDE.md
│   │   ├── JOURNEY.md                          # With multi-repo sync entries
│   │   ├── ripo-skills-main/                   # Central skills registry
│   │   │   ├── .github/workflows/
│   │   │   │   ├── distribute-skills.yml       # Distributes to 70+ repos
│   │   │   │   └── skill-contribute.yml        # Receives upstream submissions
│   │   │   └── exported-skills/                # 70+ skills with portability scores
│   │   ├── claude-admin/                       # Admin control plane (11 MCP tools)
│   │   │   └── .github/workflows/
│   │   │       └── skill-distribution-sync.yml # Manages 150+ distributions
│   │   ├── enrolled-repos-sample/              # 5 sample enrolled repos
│   │   └── docs/
│   │       ├── DISTRIBUTION-GUIDE.md           # How skill sync works
│   │       └── ENROLLMENT-CHECKLIST.md         # Steps to enroll new repo
│   │
│   └── autonomous-platform/                    # Full autonomy with Ralph Loop (Generation 3)
│       ├── README.md                           # Project overview
│       ├── CLAUDE.md
│       ├── JOURNEY.md                          # With agent decision entries
│       ├── src/
│       │   └── agent/                          # Ralph Loop implementation
│       │       ├── decision-engine.ts          # Decision-making logic
│       │       ├── skill-lifecycle.ts          # Auto-enroll/remove skills
│       │       └── secret-manager.ts           # Continuous secret rotation
│       ├── .github/workflows/
│       │   └── autonomous-main-loop.yml        # Runs every hour
│       ├── terraform/                          # Full stack (Railway, Cloudflare, N8N)
│       └── docs/
│           └── RALPH-LOOP.md                   # Decision engine documentation
│
├── docs/                                       # Operations documentation
│   ├── QUICKSTART.md                           # 5-minute setup guide
│   ├── OPERATOR.md                             # Daily operations checklist
│   ├── TROUBLESHOOTING.md                      # Common issues + solutions
│   ├── ARCHITECTURE.md                         # This-repo architecture (not template arch)
│   ├── SECURITY.md                             # Security policies (ADRs 0100-0104)
│   │
│   ├── ADR-TEMPLATE.md                         # Template for new ADRs (0200+)
│   ├── SKILL-TEMPLATE.md                       # Template for new skills
│   ├── WORKFLOW-TEMPLATE.md                    # Template for new GitHub Actions
│   │
│   ├── CONTRIBUTING.md                         # How to contribute to this repo
│   ├── CODE_OF_CONDUCT.md                      # Community guidelines
│   └── MAINTENANCE.md                          # Maintenance schedule + procedures
│
├── .claude/                                    # Claude Code configuration
│   ├── settings.json                           # Project harness settings
│   │   (can reference this file for permissions)
│   │
│   ├── agents/                                 # Custom agent prompts
│   │   ├── autonomous-orchestration.md         # Prompt for control-plane agent
│   │   └── skill-review-agent.md               # Prompt for skill auditing
│   │
│   └── skills/                                 # Custom Claude Code skills (repo-specific)
│       ├── terraform-plan-review.md
│       └── policy-audit.md
│
└── .gitignore                                  # Exclude sensitive files
    └── Contents:
        # Ignore Terraform
        .terraform/
        .terraform.lock.hcl
        *.tfstate
        *.tfstate.*
        
        # Ignore secrets
        .env
        .env.local
        terraform.tfvars (keep .example)
        secrets.json
        
        # Ignore Node/TypeScript
        node_modules/
        dist/
        *.tsbuildinfo
        
        # Ignore logs
        *.log
        
        # IDE
        .vscode/
        .idea/
        
        # OS
        .DS_Store
```

---

## Critical Configuration Files

### 1. `terraform/terraform.tfvars.example`

Template for organization-specific variables:

```hcl
# Required: Organization identifiers
github_org          = "your-github-org"        # e.g., "edri2or"
gcp_project_id      = "your-gcp-project-id"    # e.g., "or-infra-admin"
wif_pool_id         = "github-pool"            # WIF pool name (can be shared)
wif_provider_id     = "github-provider"        # WIF provider name (can be shared)

# Required: GitHub App configuration
github_app_id       = 123456                   # GitHub App ID (provisioned separately)
app_private_key_sm_secret_name = "github-app-private-key"  # GCP SM secret name

# Optional: Additional providers
enable_railway      = true                     # Deploy to Railway
enable_cloudflare   = true                     # Cloudflare edge gateway
enable_n8n         = false                     # N8N automation (requires additional setup)

# Required if enable_railway = true
railway_workspace_id = "your-railway-workspace-id"

# Required if enable_cloudflare = true
cloudflare_account_id = "your-account-id"
cloudflare_zone_id   = "your-zone-id"
cloudflare_api_token_sm_secret = "cloudflare-api-token"
```

### 2. `.github/workflows/documentation-enforcement.yml`

Validates CLAUDE.md + ADRs at commit time:

```yaml
name: Documentation Enforcement
on: [push, pull_request]

jobs:
  policy-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # OPA check
      - uses: open-policy-agent/setup-opa@v1
      - run: opa test policies/ -v
      
      # Python mirror check (zero-dependency CI)
      - run: python3 policies/scripts/check_policies.py
      
      - name: Enforce CLAUDE.md exists
        run: |
          if [ ! -f CLAUDE.md ]; then
            echo "ERROR: CLAUDE.md is required"
            exit 1
          fi
      
      - name: Enforce ADR format
        run: |
          for f in docs/adr/*.md; do
            grep -q "^# ADR-" "$f" || exit 1
            grep -q "^## Status:" "$f" || exit 1
            grep -q "^## Decision:" "$f" || exit 1
          done
```

### 3. `.claude/settings.json`

Project-specific Claude Code configuration:

```json
{
  "model": "claude-opus-4-7",
  "permissions": {
    "Bash": {
      "allowed": [
        "terraform init",
        "terraform plan",
        "terraform apply",
        "gcloud secrets",
        "git push"
      ]
    },
    "Read": {
      "allowed": ["**/*.md", "**/*.tf", ".github/workflows/**"]
    }
  },
  "hooks": {
    "before_bash_terraform": "Run policy check",
    "after_git_commit": "Log commit to JOURNEY.md"
  }
}
```

---

## File Initialization Checklist

When creating a new project from this template:

- [ ] `terraform/terraform.tfvars` — Rename from `.example` + populate org constants
- [ ] `CLAUDE.md` — Update project-specific rules (ADR ranges, team context)
- [ ] `.github/CODEOWNERS` — Add team/maintainers
- [ ] `README.md` — Update project description + links
- [ ] `skills/*/` — Review portability scores, disable org-specific skills
- [ ] `.claude/settings.json` — Set model preference + permissions
- [ ] First commit — Include bootstrap scripts output (Terraform state summary)
- [ ] First workflow run — Validate WIF → Secret Manager → GitHub App chain

---

## Size Estimates

| Component | Files | Size |
|-----------|-------|------|
| terraform/ | 15 files | ~2 MB |
| .github/workflows/ | 8 files | ~15 KB |
| policies/ | 6 files | ~30 KB |
| src/ | 20 files | ~50 KB |
| scripts/ | 10 files | ~40 KB |
| skills/ | 70+ skills | ~500 KB |
| examples/ | 3 generations | ~2 MB |
| docs/ | 15+ files | ~300 KB |
| **Total** | **150+** | **~5 MB** |

---

**End of Template Repository Structure**
