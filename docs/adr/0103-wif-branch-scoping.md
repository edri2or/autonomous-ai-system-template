# ADR-0103: Standardize WIF Attribute Conditions (Branch-Scoping)

**Date:** 2026-04-28  
**Status:** PROPOSED  
**Phase:** 4 — Architecture Decision Records  
**Evidence Base:** [Phase 3 Cross-Repo Synthesis](../state/synthesis-phase-3.md) (Section 1.5)

---

## Problem

Two of seven repositories (project-life-134, salamtak) use GCP Workload Identity Federation (WIF) with incomplete attribute conditions. Current configurations allow **feature branches** to assume GCP service account credentials, creating a privilege escalation vector.

### Current Vulnerable Configurations

**project-life-134** (`terraform/wif.tf`):
```hcl
attribute_condition = "assertion.repository == '${var.github_repository}'"
# ← Only checks repository name
# ← Does NOT check branch
```

**salamtak** (`terraform/wif.tf`):
```hcl
attribute_condition = "assertion.repository == '${var.github_repository}'"
# ← Same vulnerability
```

### Attack Scenario

1. Attacker creates feature branch `attacker/escalate` in compromised repo
2. Attacker's CI workflow runs on this branch
3. WIF exchanges OIDC token for GCP service account credentials
4. Attacker gains access to:
   - GCP Secret Manager (all secrets)
   - Terraform state (all infrastructure)
   - Deployed services (code execution)
   - Downstream repositories (via credential chain)

**Risk Severity:** HIGH (requires repo write access, but enables infrastructure takeover)

### Secure Implementations

**project-life-133** and **project-life-130** correctly scope to `main` branch:
```hcl
attribute_condition = "assertion.ref == 'refs/heads/main' && assertion.repository == '${var.github_repository}'"
```

---

## Decision

Standardize WIF attribute conditions across all 5 repos using WIF to require:
1. Repository name matches expected repo
2. Ref is exactly `refs/heads/main` (no branches, no tags)

### Standard Attribute Condition

```hcl
attribute_condition = "assertion.ref == 'refs/heads/main' && assertion.repository == '${var.github_repository}'"
```

### Rationale

- **Main branch only:** Protects infrastructure automation from feature branch exploits
- **Repository scoping:** Prevents cross-repo credential reuse
- **Immutable:** ref check is evaluated by GCP (cannot be bypassed in CI)
- **Explicit:** Clearly documents security boundary

---

## Consequences

### Benefits

✅ **Privilege Isolation:** Feature branches cannot access production secrets or infrastructure  
✅ **Attack Surface Reduction:** Only main branch CI workflows get credentials  
✅ **Compliance:** Follows principle of least privilege  
✅ **Audit Trail:** GCP logs will show which branch attempted credential exchange  
✅ **Standard Pattern:** Same condition in project-life-130/133 (proven secure)

### Drawbacks

⚠ **Reduced Flexibility:** Feature branch workflows cannot directly access GCP (must use main branch)  
⚠ **Workflow Refactoring:** Workflows that run on PR branches must be restructured  
⚠ **Local Testing:** Developers cannot use WIF locally (must use service account key escrow — see ADR-0100)

### Workaround for Feature Branches

If feature branches need to access GCP (e.g., for testing):
1. **Pull Request Workflow:** Trigger main branch workflow with parameters from PR
2. **Trusted PR Approval:** Require explicit approval before running main-branch infra operations
3. **Secrets Escrow:** Use GCP Service Account Key for local/feature branch testing (short-lived, rotated daily)

---

## Implementation Scope

**Phase 4 (Architecture Definition):**
- Define standard attribute condition template
- Document branch-scoping rationale
- Create Terraform module for WIF configuration

**Phase 5-6 (Implementation & Validation):**
1. Update project-life-134 `terraform/wif.tf`
   ```hcl
   attribute_condition = "assertion.ref == 'refs/heads/main' && assertion.repository == '${var.github_repository}'"
   ```

2. Update salamtak `terraform/wif.tf` (same change)

3. Audit all workflows that run on feature branches:
   - Identify which workflows need GCP access
   - Refactor to use main branch workflow dispatch (with parameters)
   - Add approval gates if needed

4. Test WIF exchange:
   - Main branch workflow should SUCCEED
   - Feature branch workflow should FAIL (403 Forbidden from GCP)
   - Run auth test in both branches

**Target Completion:** Before Phase 7 (final template creation)

---

## Testing Procedure

**Validate main branch WIF works:**
```bash
# In GitHub Actions workflow (main branch)
gcloud auth application-default print-access-token
# Should succeed and print token
```

**Validate feature branch WIF fails:**
```bash
# In GitHub Actions workflow (feature branch)
gcloud auth application-default print-access-token
# Should fail: 403 Forbidden or "Could not exchange token"
```

---

## Related ADRs

- **ADR-0100:** Migrate from Classic PATs to GitHub App Tokens (token chain uses WIF)
- **ADR-0104:** Token Handling for External API Calls

## References

- [GCP Workload Identity Federation: Attribute Conditions](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines#config_workload_identity_pool)
- [GitHub Actions OIDC Trust](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

---

**Status:** Ready for Phase 5-6 Implementation
