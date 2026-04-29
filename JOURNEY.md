# JOURNEY.md — Pilot Test: Create System From Template

## Session Identity
- **Branch:** `claude/pilot-test-template-system-0TIfX`
- **Repo:** `edri2or/autonomous-ai-system-template`
- **Date:** 2026-04-29
- **Goal:** Phase 9 smoke-test — verify end-to-end bootstrap of a new autonomous AI system

---

## Template Status
- **Version:** v0.4.0-alpha
- **HEAD:** `5a8168d`
- **Readiness:** ✅ All scripts valid, all workflows guarded, N8N/Railway/Cloudflare stacks ready

---

## Pilot Test Plan

### What This Session Does (Claude Code)
- [x] Created pilot test branches in both repos
- [x] Created JOURNEY.md and gate checklist
- [ ] Validate bootstrap scripts (dry-run)
- [ ] Confirm all required files present

### What Requires Human Action (GCP Cloud Shell)
1. **GATE-001:** Create GitHub App + store private key in GCP Secret Manager
2. **GATE-003:** Create bootstrap SA with required IAM roles
3. **Run:** `bash bootstrap/pre-bootstrap.sh --new-repo test-autonomous-01`
4. **Verify:** GitHub Actions results in the new repo

---

## Quick Reference

```bash
# In GCP Cloud Shell — after completing GATE-001 and GATE-003:
export GH_TOKEN="ghp_..."
git clone https://github.com/edri2or/autonomous-ai-system-template.git
cd autonomous-ai-system-template
bash bootstrap/pre-bootstrap.sh --new-repo test-autonomous-01
```

Full guide: `docs/guides/cloud-native-bootstrap.md`
Gate tracker: `docs/state/smoketest-phase-9.md` (control plane repo)

---

## Evidence Model
- **Currently Proven:** Template structure, script syntax, YAML validity
- **Needs Validation:** Live infrastructure deployment (GCP WIF, SM, Railway, Cloudflare)
- **Next:** Human executes bootstrap from GCP Cloud Shell → records results
