# ADR-0100: Migrate from Classic PATs to GitHub App Token Chain

**Date:** 2026-04-28  
**Status:** PROPOSED  
**Phase:** 4 — Architecture Decision Records  
**Evidence Base:** [Phase 3 Cross-Repo Synthesis](../state/synthesis-phase-3.md) (Section 2.1)

---

## Problem

Six of seven source repositories (project-life-130, project-life-133, ripo-bot, ripo-skills-main, claude-admin, salamtak) rely on long-lived classic Personal Access Tokens (PATs) for GitHub API automation:

- **PUSH_TARGET_TOKEN** (project-life-130, project-life-133, ripo-bot, salamtak)
- **RIPO_SKILLS_MAIN_PAT** (ripo-skills-main)
- **GH_TOKEN** (claude-admin)

### Security Risks

1. **No Operation Scoping:** Classic PATs cannot be limited to specific operations (e.g., "push only," "read-only")
2. **Long-Lived Credentials:** No automatic rotation; valid indefinitely until manually revoked
3. **Broad Repository Scope:** Cannot restrict to single repo or branch
4. **Single Point of Failure:** If compromised, attacker gains PUSH, PR approval, and workflow dispatch capabilities
5. **Systemic Exposure:** These tokens are passed via GitHub Secrets (CRITICAL+ visibility) and used in multiple workflows

### Current State

| Repo | Token Name | Used By | Classification |
|------|-----------|---------|-----------------|
| project-life-130 | PUSH_TARGET_TOKEN | skill-contribute.yml | CRITICAL |
| project-life-133 | PUSH_TARGET_TOKEN | skill-contribute.yml | CRITICAL |
| ripo-bot | PUSH_TARGET_TOKEN | skill-contribute.yml | CRITICAL |
| ripo-skills-main | RIPO_SKILLS_MAIN_PAT | 4 workflows, unprotected | CRITICAL |
| claude-admin | GH_TOKEN | tf-apply cleanup, pr-autofix.yml | CRITICAL |
| salamtak | PUSH_TARGET_TOKEN + PERSONAL_GH_TOKEN | skill-contribute.yml, orphaned | CRITICAL |

**CLAUDE.md Hard Rule:** Long-lived classic PATs are **REJECTED** for runtime authorization.

---

## Decision

Replace all classic PAT usage with ephemeral GitHub App installation tokens obtained via the secure token chain:

**Workflow:**
1. GitHub Actions OIDC token → WIF pool in GCP
2. Exchange OIDC for GCP service account token (no stored credentials)
3. Service account reads GitHub App private key from GCP Secret Manager (JIT)
4. `actions/create-github-app-token@v1` action mints:
   - **10-minute JWT** for authentication
   - **1-hour installation token** for API calls
5. Token discarded at workflow end (no storage)

### Proof of Concept

**Repos with Proven Implementation:**
- project-life-133: `.github/workflows/bootstrap.yml` uses WIF → Secret Manager → app token
- project-life-134: 9 of 10 workflows follow this pattern
- claude-admin: Short-lived GitHub App tokens used in tf-apply workflows

---

## Consequences

### Benefits

✅ **Ephemeral Credentials:** Tokens valid for 1-3600 seconds; no long-lived keys  
✅ **Fine-Grained Permissions:** GitHub App scopes limit to specific actions (repo contents, PR management, etc.)  
✅ **Automatic Rotation:** Each workflow run gets a fresh token  
✅ **Audit Trail:** Token creation logged in GCP (who/when/why)  
✅ **No Stored Secrets:** Only the App private key (encrypted in Secret Manager) and WIF provider name (public)  
✅ **Blocks Escalation:** Token expires before attacker can reuse it

### Drawbacks

⚠ **GCP Dependency:** Requires WIF pool and Secret Manager (acceptable for template, but platform-specific)  
⚠ **GitHub App Registration:** Org-level GitHub App must be pre-created (manual step in Phase 9)  
⚠ **Multi-Step Credential Exchange:** More infrastructure, but complexity is paid upfront (worthwhile)

## Implementation Scope

**Phase 4 (Architecture Definition):**
- Define GitHub App scopes and permissions
- Document credential exchange workflow
- Specify WIF attribute conditions (see ADR-0103)

**Phase 5-6 (Implementation & Validation):**
- Create GitHub App in org
- Configure WIF provider with attribute condition
- Store App private key in GCP Secret Manager
- Refactor all skill-contribute.yml and tf-apply workflows
- Rotate and revoke all classic PATs

**Target Completion:** Before Phase 7 (final template creation)

---

## Related ADRs

- **ADR-0103:** WIF Attribute Conditions (branch-scoping)
- **ADR-0104:** Token Handling for External API Calls (salamtak/OpenCode)

## References

- [GitHub App Authentication for Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [actions/create-github-app-token](https://github.com/actions/create-github-app-token)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)

---

**Status:** Ready for Phase 5 Implementation
