# Phase 9 Bootstrap - Secrets Hub Configuration

**Status:** ACTIVE (2026-04-29)  
**Project:** or-infra-templet-admin  
**Region:** Global (GCP Secret Manager)

## Overview

Dedicated GCP project created for Autonomous AI System Template bootstrap secrets management, replacing quota-limited or-infra-admin-hub.

## Secrets Hub Project Details

| Property | Value |
|----------|-------|
| Project ID | or-infra-templet-admin |
| Project Number | 974960215714 |
| Service | Google Cloud Secret Manager |
| API Status | Enabled ✓ |
| Billing Account | Linked ✓ |
| Organization | Auto-detected |

## Migrated Secrets (17 total)

### Anthropic (1)
- `ANTHROPIC_API_KEY` ✓

### Cloudflare (7)
- `CLOUDFLARE_API_TOKEN` ✓
- `CLOUDFLARE_ACCOUNT_ID` ✓ (verified 2026-04-29)
- `CLOUDFLARE_DOMAIN` ✓
- `CLOUDFLARE_EMAIL` ✓
- `CLOUDFLARE_ZONE_ID` ✓
- `CLOUDFLARE_ACCOUNT_ID_SECOND` ✓
- `CLOUDFLARE_API_TOKEN_SECOND` ✓

### AI Services (5)
- `DEEPGRAM_API_KEY` ✓
- `ELEVEN_LABS_API_KEY` ✓
- `HUGGING_FACE_API_KEY` ✓
- `OPENROUTER_API_KEY` ✓
- `REPLICATE_API_KEY` ✓

### Linear (3)
- `LINEAR_API_KEY` ✓
- `LINEAR_TEAM_ID` ✓
- `LINEAR_PROJECT_ID` ✓

### Railway (2)
- `RAILWAY_PROJECT_ID` ✓
- `RAILWAY_PROJECT_TOKEN` ✓

## Verification

✓ All 17 secrets successfully migrated from or-infra-admin-hub  
✓ CLOUDFLARE_ACCOUNT_ID verified present in target project (2026-04-29)  
✓ Secret Manager API enabled and operational  
✓ Billing account active and linked

## Bootstrap Configuration

Default secrets hub for `bootstrap/pre-bootstrap.sh`:
```bash
SECRETS_HUB_PROJECT="or-infra-templet-admin"
```

Users can override with:
```bash
./bootstrap/pre-bootstrap.sh --secrets-hub-project <custom-project-id>
```

## Related Documentation

- Decision Document: [secrets-hub-project-migration.md](../docs/decisions/secrets-hub-project-migration.md)
- Bootstrap Guide: [cloud-native-bootstrap.md](../docs/guides/cloud-native-bootstrap.md)
- GitHub Discussion: https://github.com/edri2or/claude-builder-pro/discussions/1

---

**Last Updated:** 2026-04-29  
**Maintained By:** Phase 9 Bootstrap Implementation
