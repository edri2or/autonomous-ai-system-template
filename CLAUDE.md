# Phase 9 Bootstrap — Operational Memory

**Status:** ACTIVE (2026-04-29)  
**Secrets Hub Project:** or-infra-templet-admin

## Quick Reference

**Default secrets hub:** `or-infra-templet-admin` (project ID: 974960215714)

**Bootstrap scripts use this as default:**
- `bootstrap/pre-bootstrap.sh` — Cloud Shell one-command bootstrap
- `bootstrap/bootstrap-new-project.sh` — Post-gate new project creation

**Override if needed:**
```bash
./bootstrap/pre-bootstrap.sh --secrets-hub-project <custom-project-id>
```

## Secrets Hub Architecture

Full specification: **[ADR-0105: Centralized Secrets Hub](../docs/adr/0105-centralized-secrets-hub.md)**

Hub contains:
- GitHub App credentials (always required)
- Provider tokens (Railway, Cloudflare, N8N) — conditional

## Current Implementation

- **Project created:** 2026-04-29 in Cloud Shell
- **Billing:** Active and verified
- **Secret Manager API:** Enabled
- **17 secrets migrated:** From or-infra-admin-hub → or-infra-templet-admin ✓

## Related Files

- [ADR-0105: Centralized Secrets Hub](../docs/adr/0105-centralized-secrets-hub.md) — Architecture & decision
- [Cloud-Native Bootstrap Guide](../docs/guides/cloud-native-bootstrap.md) — Step-by-step user guide
- [bootstrap/pre-bootstrap.sh](./bootstrap/pre-bootstrap.sh) — Implementation (Cloud Shell)
- [bootstrap/bootstrap-new-project.sh](./bootstrap/bootstrap-new-project.sh) — Implementation (template)

---

**Last Updated:** 2026-04-29  
**Maintained by:** Phase 9 Bootstrap
