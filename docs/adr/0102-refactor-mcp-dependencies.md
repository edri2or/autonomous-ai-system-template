# ADR-0102: Refactor mcp__github__* Tool Dependencies

**Date:** 2026-04-28  
**Status:** PROPOSED  
**Phase:** 4 — Architecture Decision Records  
**Evidence Base:** [Phase 3 Cross-Repo Synthesis](../state/synthesis-phase-3.md) (Section 2.3)

---

## Problem

Nine or more skills in ripo-bot and ripo-skills-main depend on Claude Code's built-in GitHub MCP server at runtime:

### Affected Skills

**ripo-bot:**
- skill-centralizer
- audit-github-tokens
- cross-repo-success-synthesis
- auto-subscribe-pr-hook
- migrate-pat-secrets-to-terraform
- gcp-wif-bootstrap
- (+ 3 more)

**ripo-skills-main:**
- skill-centralizer
- audit-github-tokens
- cross-repo-success-synthesis
- gcp-wif-bootstrap
- auto-subscribe-pr-hook
- (listed in `allowed-tools`)

### Architectural Issue

Per **CLAUDE.md Hard Rule #7:**
> "NEVER introduce Claude Code built-in MCP mechanisms into the project plan"

And **Hard Rule #8:**
> "NEVER adopt a historically proven pattern without current validation"

These skills rely on `mcp__github__*` tools, which:
1. Are Claude Code built-in features (not portable)
2. Cannot be copied into final template
3. Require active Claude Code session to invoke
4. Are not available in production automation contexts

### Current State

**Classification:** REJECTED (High Risk)  
**Blocker:** Template adoption impossible while skills depend on mcp__github__*

---

## Decision

Refactor all affected skills to use **explicit GitHub API calls** via curl + token authentication instead of relying on Claude Code's MCP tools.

### Pattern: From MCP Tools to Explicit API

**Before (REJECTED - MCP-dependent):**
```typescript
import { invokeAgent } from "@anthropic/sdk";
// Calls mcp__github__search_code, mcp__github__get_file_contents, etc.
const result = await mcp.tools.github.search_code({ query: "..." });
```

**After (PORTABLE - Curl + Token):**
```bash
#!/bin/bash
TOKEN="${GITHUB_APP_TOKEN}"  # From GitHub App token chain (ADR-0100)

# Explicit curl call to GitHub API
curl -s -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/search/code?q=${QUERY}" | jq .
```

### Skill Refactoring Template

1. **Identify mcp calls** in skill source code
2. **Map to GitHub API endpoints** (docs: https://docs.github.com/en/rest)
3. **Replace with curl + jq** (or Python requests)
4. **Use GITHUB_APP_TOKEN environment variable** (set by ADR-0100 token chain)
5. **Add error handling** for HTTP failures
6. **Test portability** by running without Claude Code MCP

---

## Consequences

### Benefits

✅ **Portability:** Skills work in any execution context (GitHub Actions, n8n, Local CLI, Final Template)  
✅ **No Platform Lock-In:** Does not depend on Claude Code features  
✅ **Transparency:** Explicit API calls are auditable and easier to understand  
✅ **Testability:** Can mock GitHub API responses in unit tests  
✅ **Security:** Token passed as standard Authorization header (not MCP framework)

### Drawbacks

⚠ **Code Verbosity:** curl + jq is more verbose than mcp tool invocations  
⚠ **Error Handling:** Must explicitly handle GitHub API rate limits and errors  
⚠ **Learning Curve:** Team must understand GitHub API conventions  
⚠ **Testing Burden:** Need to mock GitHub API responses instead of relying on framework

---

## Implementation Scope

**Phase 4 (Architecture Definition):**
- Document GitHub API endpoints for each mcp tool used
- Create curl/jq template patterns for common operations
- Define error handling conventions (rate limits, auth failures, transient errors)

**Phase 5-6 (Refactoring & Validation):**
1. For each affected skill:
   - Audit mcp__github__* tool usage
   - Map to GitHub API endpoints
   - Refactor with curl + token
   - Add unit tests (mock API responses)
   - Validate in non-Claude execution context (e.g., bash only)

2. Integration testing:
   - Run skill in GitHub Actions (with GITHUB_APP_TOKEN from ADR-0100)
   - Run skill in n8n workflow (with explicit token)
   - Run skill locally (with GITHUB_APP_TOKEN env var)

3. Remove `allowed-tools: [mcp__github__*]` from affected SKILL.md files

**Target Completion:** Before Phase 7 (final template creation)

### Skills Priority

| Skill | Complexity | Priority |
|-------|-----------|----------|
| auto-subscribe-pr-hook | Low | HIGH |
| gcp-wif-bootstrap | Medium | HIGH |
| skill-centralizer | High | MEDIUM |
| audit-github-tokens | Medium | MEDIUM |
| cross-repo-success-synthesis | High | MEDIUM |

---

## Example: auto-subscribe-pr-hook Refactoring

**Before (MCP):**
```typescript
mcp__github__subscribe_pr_activity({
  owner: "org",
  repo: "repo",
  pullNumber: 123
});
```

**After (Explicit API via curl):**
```bash
#!/bin/bash
PR_OWNER="$1"
PR_REPO="$2"
PR_NUMBER="$3"
GITHUB_APP_TOKEN="$4"

# Fetch PR details to trigger subscription via GitHub API polling
curl -s -H "Authorization: token ${GITHUB_APP_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${PR_OWNER}/${PR_REPO}/pulls/${PR_NUMBER}" \
  | jq '.id, .state, .updated_at'

# Note: PR subscription is implicit via GitHub Actions webhook integration.
# To subscribe to PR events, ensure GitHub App has "pull_request" event permission
# and configure webhook at https://github.com/settings/apps/your-app-name/webhooks
```

---

## Related ADRs

- **ADR-0100:** Migrate from Classic PATs to GitHub App Tokens
- **ADR-0101:** Explicit Secret Passing

## References

- [GitHub REST API Documentation](https://docs.github.com/en/rest)
- [GitHub Actions: Authenticating with GitHub](https://docs.github.com/en/actions/security-guides/automatic-token-authentication)
- [curl + GitHub API Examples](https://docs.github.com/en/rest/guides/getting-started-with-the-rest-api)

---

**Status:** Ready for Phase 5-6 Implementation
