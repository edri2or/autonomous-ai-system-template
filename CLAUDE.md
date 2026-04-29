# CLAUDE.md — Autonomous AI System Template

## Hard Rules (Never Break)

- **NEVER ask the user to set a GitHub secret manually.** All GitHub secrets are set
  programmatically by `bootstrap/pre-bootstrap.sh` or Claude Code sessions via the GitHub API.
- **NEVER ask the user to download a service account key.** Cloud Shell uses Application Default
  Credentials (ADC); SA keys must not be created or stored for bootstrap operations.
- **NEVER ask the user to navigate GitHub Settings** beyond (1) creating a GitHub App via the URL
  shown by `pre-bootstrap.sh` and clicking "Create", and (2) clicking "Install" to approve it.
- **NEVER store an SA key in GitHub Secrets.** WIF (Workload Identity Federation) is the only
  allowed mechanism for GitHub Actions → GCP authentication after bootstrap completes.
- NEVER print, commit, log, or expose token/secret/PEM values.

## Secrets Hub Quick Reference

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

## Related Files

- [ADR-0105: Centralized Secrets Hub](../docs/adr/0105-centralized-secrets-hub.md) — Architecture & decision
- [Cloud-Native Bootstrap Guide](../docs/guides/cloud-native-bootstrap.md) — Step-by-step user guide
- [bootstrap/pre-bootstrap.sh](./bootstrap/pre-bootstrap.sh) — Implementation (Cloud Shell)
- [bootstrap/bootstrap-new-project.sh](./bootstrap/bootstrap-new-project.sh) — Implementation (template)

---

**Last Updated:** 2026-04-29
