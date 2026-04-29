# ADR-0105: Automated GitHub App Creation via Manifest Flow + Cloud Shell Web Preview

**Date:** 2026-04-29  
**Status:** Accepted  
**Evidence:** Currently Proven

## Context

GATE-001 requires GitHub App creation with automatic credential storage in GCP Secret Manager. Previous implementation required:
- Manual GitHub UI navigation
- Browser-based .pem file download
- Manual file upload to Secret Manager
- High risk of credential exposure

This violates the security principle: **NEVER ask users to download or handle credentials manually.**

## Decision

Implement automated GitHub App creation using GitHub's **Manifest Flow** combined with **Cloud Shell Web Preview**:

1. Script generates manifest JSON with all required permissions
2. Script uses Cloud Shell's built-in `$WEB_HOST` to construct public redirect URL: `https://8080-$WEB_HOST/callback`
3. Script starts Python HTTP server listening on port 8080
4. User clicks one link and performs two GitHub UI clicks (Create + Install)
5. GitHub redirects to Python server with temporary code
6. Script exchanges code for credentials (id, pem, webhook_secret, client_id, client_secret)
7. Script stores all credentials in GCP Secret Manager
8. Script cleans up HTTP server and exits

**Time to complete:** ~2 minutes total (mostly waiting for GitHub to process)  
**User actions:** 2 clicks (both on GitHub UI)  
**Credentials exposure:** Zero — no downloads, no pastes, no terminal output

## Rationale

### Why Manifest Flow?

- **Standard GitHub pattern:** Documented in official GitHub API
- **Proven in production:** Used by Probot (Node.js GitHub App framework)
- **Code exchange is secure:** Temporary code is one-time use, 1-hour expiration
- **No PAT needed:** Unlike GitHub Settings UI, manifest flow doesn't require a pre-existing token
- **Automatic key generation:** GitHub generates the private key and returns it in the exchange response

### Why Cloud Shell Web Preview?

- **Eliminates localhost complexity:** No need for ngrok, tunneling, or port forwarding
- **Built-in to Cloud Shell:** `$WEB_HOST` environment variable is always available
- **Public HTTPS URL:** GitHub can reach it directly with no firewall issues
- **No additional cost:** Built into GCP Cloud Shell
- **Standard port range:** Ports 2000–65000 supported natively

### Security Advantages

✅ **PEM never downloaded:** Piped directly from curl response to `gcloud secrets`  
✅ **No local files:** No .pem lingering in Downloads or temp directories  
✅ **No terminal output:** Credentials never printed or logged  
✅ **No clipboard:** No copy/paste risk  
✅ **Automatic cleanup:** shred used to securely delete temp files  

## Alternatives Considered

### A: Manual GitHub Settings UI
**Rejected:** Requires user to download .pem and manually upload to Secret Manager (high credential exposure risk)

### B: GitHub API classic PAT flow
**Rejected:** Requires user to create a PAT (classic PATs have broad scopes, security anti-pattern)

### C: Ngrok or similar tunneling
**Rejected:** Adds external dependency, requires signup/token, not available in Cloud Shell sandboxed environment

## Implementation

File: `bootstrap/pre-bootstrap.sh` PHASE 1

Key changes:
- Use Cloud Shell `$WEB_HOST` environment variable for redirect URL
- Start Python HTTP server on port 8080 to receive callback
- Poll for code file instead of prompting user to paste
- Automatic code exchange and credential storage

## Consequences

### Positive
- ✅ Zero credential exposure risk
- ✅ Fully automated (2 user clicks only)
- ✅ Works in any Cloud Shell session
- ✅ No external dependencies
- ✅ Consistent with GitHub best practices

### Negative
- ⚠️ Requires Python 3 (standard in Cloud Shell)
- ⚠️ Requires gcloud CLI (standard in Cloud Shell)
- ⚠️ HTTP server binds port 8080 (fails if port in use, but unlikely in Cloud Shell)

## References

- GitHub App Manifest Flow: https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest
- Cloud Shell Web Preview: https://docs.cloud.google.com/shell/docs/using-web-preview
- Probot (Node.js GitHub App framework using manifest flow): https://probot.github.io/