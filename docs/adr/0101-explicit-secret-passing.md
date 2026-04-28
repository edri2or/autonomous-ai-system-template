# ADR-0101: Replace secrets:inherit with Explicit Secret Passing

**Date:** 2026-04-28  
**Status:** PROPOSED  
**Phase:** 4 — Architecture Decision Records  
**Evidence Base:** [Phase 3 Cross-Repo Synthesis](../state/synthesis-phase-3.md) (Section 2.2)

---

## Problem

Four repositories use `secrets: inherit` to pass **all parent workflow secrets** to external reusable workflows:

1. **ripo-bot:** `skill-sync.yml` → `edri2or/ripo-skills-main@main` (secrets: inherit)
2. **ripo-skills-main:** `templates/skill-sync.yml` → distributed to **70+ enrolled repos** (secrets: inherit)
3. **claude-admin:** `skill-sync.yml` → `edri2or/ripo-skills-main@main`
4. **salamtak:** `skill-sync.yml` → `edri2or/ripo-skills-main@main`

### Supply-Chain Vulnerability

| Risk | Impact | Severity |
|------|--------|----------|
| **Secrets Exposure** | If ripo-skills-main is compromised, attacker receives: PUSH_TARGET_TOKEN, ANTHROPIC_API_KEY, CLOUDFLARE_ACCOUNT_API_TOKEN, GCP_WORKLOAD_IDENTITY_PROVIDER, all others | CRITICAL |
| **Scale** | 70+ enrolled repos simultaneously exposed if ripo-skills-main is compromised | CRITICAL |
| **Non-Pinned Reference** | `@main` allows ripo-skills-main maintainers to silently change behavior | CRITICAL |
| **No Audit Trail** | Cannot see which secrets are passed to which workflow | HIGH |

### Current State

**Leaked Secrets (if ripo-skills-main is compromised):**
- PUSH_TARGET_TOKEN (write access to org repos)
- ANTHROPIC_API_KEY (Claude API access)
- CLOUDFLARE_ACCOUNT_API_TOKEN (Cloudflare account control)
- GCP_WORKLOAD_IDENTITY_PROVIDER (GCP service account access)
- All other secrets in 70+ repos

**Audit Status:** NONE — secrets passed without visibility

---

## Decision

### 1. Replace `secrets: inherit` with Explicit Secret Passing

**Before (VULNERABLE):**
```yaml
jobs:
  sync-skills:
    uses: edri2or/ripo-skills-main/.github/workflows/skill-sync.yml@main
    secrets: inherit  # ← Passes ALL secrets
```

**After (HARDENED):**
```yaml
jobs:
  sync-skills:
    uses: edri2or/ripo-skills-main/.github/workflows/skill-sync.yml@<SHA>
    secrets:
      PUSH_TARGET_TOKEN: ${{ secrets.PUSH_TARGET_TOKEN }}
      # Only pass secrets explicitly needed by the reusable workflow
```

### 2. Pin Reusable Workflow to Commit SHA

**Before:**
```yaml
uses: edri2or/ripo-skills-main/.github/workflows/skill-sync.yml@main
```

**After:**
```yaml
uses: edri2or/ripo-skills-main/.github/workflows/skill-sync.yml@abc123def456789
```

**Rationale:**
- `@main` allows ripo-skills-main to silently change workflow behavior
- SHA pinning ensures reproducible, auditable workflow execution
- Updates require explicit PR review

---

## Consequences

### Benefits

✅ **Least Privilege:** Only required secrets passed to external workflow  
✅ **Audit Trail:** Each secret explicitly documented in workflow file  
✅ **Immutable Reference:** SHA pinning prevents silent behavior changes  
✅ **Supply-Chain Security:** Reduces blast radius if external repo is compromised  
✅ **Org-Wide Consistency:** Standard pattern across all 70+ enrolled repos

### Drawbacks

⚠ **Maintenance Overhead:** Updates to ripo-skills-main require SHA bumps (mitigated by automation)  
⚠ **Workflow File Verbosity:** More lines per secret (acceptable for security)  
⚠ **Cross-Repo Coordination:** Changes to ripo-skills-main require downstream updates (Phase 6 task)

---

## Implementation Scope

**Phase 4 (Architecture Definition):**
- Define required secrets for skill-sync.yml
- Document secret scoping rules
- Create template for explicit secret passing

**Phase 5-6 (Implementation & Validation):**
- Update all 4 primary repos
- Update all 70+ enrolled repos via distribute-workflow-template.yml
- Audit ripo-skills-main for credential logging or exfiltration
- Add CI gate to block secrets:inherit in new workflows

**Target Completion:** Before Phase 7 (final template creation)

### Workflow Audit

**Questions for ripo-skills-main (Phase 5):**
1. Does the skill-sync.yml reusable workflow log request bodies or headers?
2. Are secrets ever printed to workflow logs?
3. Are secrets passed to external APIs (OpenRouter, Linear, N8N)?
4. Are secrets stored in any files that might be cached or committed?

---

## Related ADRs

- **ADR-0100:** Migrate from Classic PATs to GitHub App Tokens
- **ADR-0104:** Token Handling for External API Calls

## References

- [GitHub Actions: Using Secrets in Workflows](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idsecrets)
- [Reusable Workflows Best Practices](https://docs.github.com/en/actions/using-workflows/reusing-workflows)

---

**Status:** Ready for Phase 5 Implementation
