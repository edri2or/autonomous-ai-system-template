# ADR-0104: Token Handling for External API Calls

**Date:** 2026-04-28  
**Status:** PROPOSED  
**Phase:** 4 — Architecture Decision Records  
**Evidence Base:** [Phase 3 Cross-Repo Synthesis](../state/synthesis-phase-3.md) (Section 2.4)

---

## Problem

**Salamtak** exposes GitHub PAT in plaintext in HTTP request bodies when calling external APIs, creating a critical credential exposure vulnerability.

### Vulnerable Code

**Location:** `services/agent-webhook/main.py` (lines 120-130)

```python
def call_opencode_api(prompt: str, gh_token: str) -> dict:
    response = requests.post(
        "https://api.opencode.ai/v1/run",
        json={
            "GH_TOKEN": gh_token,      # ← TOKEN IN REQUEST BODY (PLAINTEXT)
            "prompt": prompt,
            "org_id": ORG_ID,
            "repo_name": REPO_NAME
        }
    )
    return response.json()
```

### Attack Scenario

1. **Request Body Logging:** If OpenCode logs request bodies (standard practice), token is exposed in their infrastructure logs
2. **Proxy/MITM:** If any proxy/load balancer logs requests, token is captured
3. **Caching:** Token might be cached in intermediate HTTP caches
4. **Incident History:** If OpenCode is ever compromised or audited, attackers/auditors gain GitHub access

### Risk Assessment

| Risk | Severity | Likelihood | Impact |
|------|----------|-----------|--------|
| **Credential Exposure** | CRITICAL | HIGH | Full GitHub access (push, PR approval, workflow dispatch) |
| **Non-Repudiation** | HIGH | MEDIUM | Attacker actions appear to come from Salamtak repo |
| **Scope:** | CRITICAL | HIGH | Affects all 70+ enrolled repos (if PUSH_TARGET_TOKEN used) |

---

## Decision

Replace token-in-request-body with industry-standard **HTTP Authorization header** for all external API calls.

### Pattern: HTTP Bearer Token in Authorization Header

**Before (VULNERABLE):**
```python
response = requests.post(
    "https://api.opencode.ai/v1/run",
    json={"GH_TOKEN": gh_token, "prompt": prompt}  # Token in request body (logged)
)
```

**After (HARDENED):**
```python
response = requests.post(
    "https://api.opencode.ai/v1/run",
    headers={"Authorization": f"Bearer {gh_token}"},
    json={"prompt": prompt}  # No token in body
)
```

### OAuth2 Best Practices

1. **Authorization Header Only:** Token sent ONLY in HTTP header
2. **No Request Body:** Tokens never included in JSON/form-encoded payloads
3. **HTTPS Required:** TLS encryption mandatory for all token transmission
4. **Credential Logging Audit:** Verify external API does NOT log Authorization headers
5. **Token Rotation:** Implement short-lived tokens where possible (see ADR-0100)

---

## Implementation Options

### Option A: Use HTTP Authorization Header (Recommended)
**If OpenCode API supports Bearer token authentication:**
```python
response = requests.post(
    "https://api.opencode.ai/v1/run",
    headers={"Authorization": f"Bearer {gh_token}"},
    json={"prompt": prompt}
)
```

**Advantages:**
- ✅ Industry standard (RFC 6750)
- ✅ Prevents request body logging
- ✅ Compatible with HTTP caching standards
- ✅ Supported by most APIs

### Option B: Use OAuth2 Flow
**If OpenCode supports OAuth2:**
```python
# Instead of passing token, exchange for OpenCode OAuth token
oauth_token = exchange_github_token_for_opencode_oauth(gh_token)
response = requests.post(
    "https://api.opencode.ai/v1/run",
    headers={"Authorization": f"Bearer {oauth_token}"},
    json={"prompt": prompt}
)
```

**Advantages:**
- ✅ Limits scope to OpenCode-specific operations only
- ✅ Rotation managed by OpenCode
- ✅ User explicitly authorizes OpenCode access (approval flow)

### Option C: Reject OpenCode Integration
**If neither option above is viable:**
```python
# REJECT: salamtak OpenCode integration
# Reason: Credential exposure risk cannot be mitigated
```

**Rationale:**
- If OpenCode cannot support secure token passing, the security risk is unacceptable for template adoption

---

## Consequences

### Benefits (Option A or B)

✅ **Prevents Logging Exposure:** Authorization headers are not typically logged  
✅ **Standards Compliant:** Follows OAuth2/HTTP best practices  
✅ **Transparency:** Clear where credentials are used  
✅ **Audit Trail:** API providers should have policies against logging Authorization headers

### Drawbacks

⚠ **API Integration Effort:** Must coordinate with OpenCode team if they don't support Bearer auth  
⚠ **Token Handling:** Still need secure token rotation (see ADR-0100)  
⚠ **Verification Required:** Must audit OpenCode logging practices (Phase 5 validation gate)

---

## Implementation Scope

**Phase 4 (Architecture Definition):**
- Define credential passing standards for all external API calls
- Document Authorization header pattern
- Specify token rotation requirements (see ADR-0100)

**Phase 5 (Validation & Implementation):**

1. **Contact OpenCode:** Determine API authentication method
   - Does OpenCode support Bearer token in Authorization header?
   - What is their logging/security policy?
   - Can they guarantee no request body logging?

2. **If Option A/B viable:**
   - Refactor `services/agent-webhook/main.py` to use Authorization header
   - Implement token rotation (see ADR-0100)
   - Add unit test: verify token NOT in request body
   - Add integration test: call OpenCode API with mocked response

3. **If Option C (rejection):**
   - Remove OpenCode integration from salamtak
   - Document rationale in CLAUDE.md
   - Archive salamtak as reference (not template)

**Validation Gate (Phase 5):**
- [ ] OpenCode API documentation reviewed
- [ ] Credential passing method confirmed secure
- [ ] No request body logging verified
- [ ] Refactored code tested end-to-end

**Target Completion:** Before Phase 7 (final template creation)

---

## Standards Reference

**HTTP Authorization Header (RFC 7235):**
```http
Authorization: Bearer <token>
```

**OAuth2 Bearer Token (RFC 6750):**
```http
Authorization: Bearer <access_token>
```

**Anti-Pattern (NEVER use):**
```json
{"api_key": "...", "auth_token": "...", "secret": "..."}
```

---

## Related ADRs

- **ADR-0100:** Migrate from Classic PATs to GitHub App Tokens (ephemeral tokens support this pattern)
- **ADR-0101:** Explicit Secret Passing
- **ADR-0102:** Refactor mcp__github__* Dependencies

## References

- [RFC 6750: OAuth 2.0 Bearer Token Usage](https://tools.ietf.org/html/rfc6750)
- [RFC 7235: HTTP Authentication](https://tools.ietf.org/html/rfc7235)
- [OWASP: Credentials in URLs](https://owasp.org/www-community/vulnerabilities/Credentials_in_URLs)

---

**Status:** Ready for Phase 5 Validation (Gate: OpenCode API audit required)
