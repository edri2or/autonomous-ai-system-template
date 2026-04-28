# JOURNEY.md Format Specification

**Date:** 2026-04-28  
**Related Primary Document:** docs/state/architecture-phase-6.md (Part 1.3)  
**Purpose:** Define the structure, format, and validation rules for JOURNEY.md session audit trails

---

## Overview

**JOURNEY.md** is an immutable session audit trail recording all autonomous agent activity, decisions, and outcomes. Unlike code comments (which rot), JOURNEY.md provides timestamped evidence for verification and learning.

---

## File Location & Initialization

**Location:** Repository root → `JOURNEY.md`

**Initial Content:**
```markdown
# JOURNEY.md — Session Audit Trail

**Project:** [Project Name]
**Created:** [YYYY-MM-DD]
**Description:** Autonomous agent activity log for [project context]

---

## Sessions

*(Session entries added chronologically below)*
```

---

## Entry Structure

Each session adds a new section. Format:

```markdown
## Session [SESSION_ID]

**Date:** YYYY-MM-DDTHH:MM:SSZ  
**Agent:** [Agent Name, e.g., claude-sonnet-4-6]  
**Status:** [IN_PROGRESS | COMPLETE | BLOCKED]  
**Duration:** [HH:MM or "ongoing"]  

### Summary
[1-2 sentence overview of what the agent did]

### Actions Taken
- [Bullet list of concrete actions]
- [Created: file/PR #123]
- [Merged: PR #456]
- [Committed: abc1234def567]

### Decisions Made
- [ADR-XXXX created/updated]
- [Configuration changed: key from A to B]
- [Architecture pattern adopted: name]

### Evidence
- **PR:** [#123 link]
- **Commit:** [abc1234def567]
- **Artifacts:** [links to generated files]
- **Test Results:** [pass/fail summary]

### Open Items
- [ ] Item 1 (flagged for human review or next session)
- [ ] Item 2

### Notes
[Optional: Context, assumptions, ambiguities for future sessions]

---
```

---

## Field Definitions

### Date
**Format:** ISO 8601 with timezone  
**Example:** `2026-04-28T14:32:15Z`  
**Purpose:** Sort sessions chronologically; timestamp for audit trail

### Agent
**Format:** Agent name or identity  
**Examples:**
- `claude-sonnet-4-6`
- `human-reviewer (alice@example.com)`
- `automated-policy-check`
- `webhook-dispatcher`

**Purpose:** Track which agent/human made decisions (for accountability)

### Status
**Allowed Values:**
- `IN_PROGRESS` — Session still running (incomplete)
- `COMPLETE` — All planned work finished successfully
- `BLOCKED` — Hit a blocker (documented in Open Items)
- `ROLLED_BACK` — Changes reverted (document why in Notes)

**Purpose:** Quick status check for operators

### Duration
**Format:** `HH:MM` or `[start_time - end_time]`  
**Example:** `00:45` or `14:30 - 15:15` (in same timezone as Date)  
**Purpose:** Track agent efficiency and wall-clock time

---

## Actions Taken

**Subsection for concrete outputs.** Use consistent format:

```markdown
### Actions Taken
- Created: `terraform/wif.tf` (WIF configuration)
- Modified: `.github/workflows/bootstrap.yml` (add validation step)
- Deleted: `scripts/old-bootstrap.sh` (deprecated)
- Committed: `main` branch, commit `abc1234` ("feat: WIF bootstrap")
- Merged: PR #47 (3 reviews, 0 blockers)
- Triggered: GitHub Actions run #105 (bootstrap workflow)
- Deployed: N8N instance to Railway workspace (service healthy)
```

**Key Identifiers:**
- File paths (relative to repo root)
- PR/Issue #numbers (linkable)
- Commit SHAs (short form: 7 chars minimum)
- GitHub Actions run IDs

---

## Decisions Made

**Subsection for architectural/policy decisions.**

```markdown
### Decisions Made
- ADR-0200 created: "Project charter for my-autonomous-project"
- ADR-0201 proposed: "Use Railway instead of GCP Cloud Run" (pending human review)
- Security Policy: Enforce `secrets: inherit` block (enabled in policy checks)
- Skill Distribution: Enroll 5 new repos in multi-repo distribution pipeline
- Token Rotation: Scheduled weekly Cloudflare token rotation job
```

**Traceable to:**
- ADR documents (version control)
- Policy enforcement logs (CI/CD records)
- Configuration files (Git diffs)

---

## Evidence

**Subsection linking to verifiable artifacts.**

```markdown
### Evidence
- **PR:** #47 (3 commits, 2 approvals)
- **Commit:** abc1234def567 ("feat: add WIF bootstrap")
- **Test Results:** 
  - Policy enforcement: PASS (24/24 checks)
  - E2E bootstrap: PASS (9/9 phases)
- **Artifacts:** 
  - `terraform/terraform.tfstate` (GCP resources created)
  - `.github/logs/bootstrap-run-105.json` (workflow output)
- **Screenshots/Logs:** [link to external storage if >1MB]
```

**Purpose:** Auditors can verify claims without running processes again

---

## Open Items

**Subsection for incomplete work or blockers.**

```markdown
### Open Items
- [ ] ADR-0201 pending human review (security implications unclear)
- [ ] Railway workspace migration (blocked by BLOCKER-V5-NETWORK)
- [ ] 3 repos not responding to skill distribution workflow
- [ ] Cloudflare DNS CNAME needs manual verification
```

**Checkbox states:**
- `[ ]` = Incomplete (to-do for next session)
- `[x]` = Complete (crossed off after resolution)

**Purpose:** Tracks continuity between sessions; helps operators see what's pending

---

## Notes

**Optional: Free-form context for future sessions.**

```markdown
### Notes
- Assumptions: Assumed Railway workspace ID is stable (unverified — see BLOCKER-V5-NETWORK)
- Ambiguities: Three enrolled repos have conflicting ADRs; unclear which policy applies
- Root Causes: Token rotation failed because Terraform SA lacks updated Cloud Run permissions
- Workarounds Applied: Manually created Cloudflare token (normally automated)
- Learn for Next Time: The skill distribution workflow expects exact YAML structure; took 2 hrs debugging indentation
```

**Purpose:** Captures tribal knowledge; helps future agents avoid mistakes

---

## Validation Rules

### Mandatory Fields per Session
- `Date` (required, ISO 8601)
- `Agent` (required, identifies actor)
- `Status` (required, must be one of: IN_PROGRESS, COMPLETE, BLOCKED, ROLLED_BACK)
- `Summary` (required, 1-2 sentences)
- `Actions Taken` (required if Status != IN_PROGRESS, at least one bullet)

### Optional Fields
- `Duration` (recommended if session is COMPLETE or BLOCKED)
- `Decisions Made` (include if any ADRs created)
- `Evidence` (include if claiming success)
- `Open Items` (include if Status = BLOCKED or incomplete)
- `Notes` (include if context needed for next session)

### Consistency Checks
- No future dates (Date ≤ now)
- No duplicate session IDs
- If Status = COMPLETE, all Open Items should be empty (or explain why)
- If Status = BLOCKED, at least one Open Item must explain blocker
- Commit SHAs must be valid (can be verified with `git log`)
- PR #numbers must be valid (can be looked up on GitHub)

---

## Example: Complete Session Entry

```markdown
## Session 2026-04-28-001

**Date:** 2026-04-28T14:22:33Z  
**Agent:** claude-sonnet-4-6  
**Status:** COMPLETE  
**Duration:** 01:15  

### Summary
Bootstrap infrastructure for new project (my-autonomous-project). Set up GCP WIF, Secret Manager, GitHub App. All 9 phases passed.

### Actions Taken
- Created: `terraform/main.tf`, `terraform/wif.tf`, `terraform/secrets.tf`
- Modified: `terraform/terraform.tfvars` (injected org constants)
- Executed: Terraform init → plan → apply (5m 32s)
- Created: GitHub repository `edri2or/my-autonomous-project`
- Triggered: `.github/workflows/autonomous-control-plane.yml` (run #247)
- Committed: `main` branch, commit `2c86733` ("Bootstrap: Initial Terraform state")

### Decisions Made
- ADR-0200 created: "Project Charter for my-autonomous-project"
- WIF attribute condition scoped to `refs/heads/main` (per ADR-0103)
- Skill distribution: Enabled (70+ skills will sync automatically)

### Evidence
- **Terraform Apply:** 17 GCP resources created (state file: 2.4KB)
- **GitHub App:** Installed on new repo (permissions: Read/Write contents + actions)
- **Workflow Run:** #247 completed successfully (14m 22s)
- **Policy Checks:** All 24 passed (no secrets:inherit, no classic PATs, no mcp__)
- **Test Output:** E2E bootstrap test PASS (9/9 phases)

### Open Items
- [ ] Manual: Verify GCP WIF pool still accessible with valid credentials (Phase 7)
- [ ] Manual: Test Railway deployment (if enabled) in Phase 8

### Notes
- WIF attribute condition passed validation gate; will unblock provider validation in Phase 7
- No issues encountered; bootstrap ran cleanly on first attempt
- Next step: Trigger autonomous agent to create ADR-0201+ for project-specific decisions

---
```

---

## Integration with CI/CD

### GitHub Actions Hook

Workflows can append to JOURNEY.md:

```yaml
- name: Record session in JOURNEY.md
  if: always()
  run: |
    cat >> JOURNEY.md << 'EOF'
## Session $(date -u +%Y-%m-%d-%H-%M-%S)

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Agent:** github-actions-bootstrap
**Status:** $([ $? -eq 0 ] && echo "COMPLETE" || echo "BLOCKED")
**Duration:** $(( $(date +%s) - $START_TIME )) seconds

### Actions Taken
- Executed bootstrap workflow run #${{ github.run_number }}
- Created: [files modified]
- Committed: ${{ github.sha }}

### Evidence
- **Workflow:** https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}

EOF
    git add JOURNEY.md
    git commit -m "session: append bootstrap run results"
    git push origin main
```

---

## Querying JOURNEY.md

**List recent sessions:**
```bash
grep "^## Session" JOURNEY.md | tail -10
```

**Find all BLOCKED sessions:**
```bash
grep -A 2 "^## Session" JOURNEY.md | grep -B 2 "BLOCKED"
```

**Extract all ADRs created:**
```bash
grep "ADR-[0-9]" JOURNEY.md | sort -u
```

**Verify all commits referenced:**
```bash
grep "Commit:" JOURNEY.md | awk '{print $NF}' | while read sha; do git log --oneline | grep "^$sha" || echo "MISSING: $sha"; done
```

---

## Governance

### Who Writes
- Autonomous agents (automated appends)
- Human operators (manual entries after manual actions)
- CI/CD workflows (automated session summaries)

### Who Reads
- Operators (daily: check Open Items, Status)
- Auditors (compliance: verify decisions + evidence)
- Future agents (context: learn from past sessions)

### Who Owns
- Repository owner is the source of truth (JOURNEY.md in main branch)
- Never rewrite history (JOURNEY.md is append-only)
- If error in entry: add new corrective entry, don't delete

### Retention
- Keep indefinitely (immutable audit trail)
- Rotate to archive if file exceeds 1MB
- Archive naming: `JOURNEY-2026-Q1.md`, `JOURNEY-2026-Q2.md`, etc.

---

**End of JOURNEY.md Format Specification**
