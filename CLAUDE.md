# CLAUDE.md — Autonomous AI System Template

## Identity
This repository (`edri2or/autonomous-ai-system-template`) is the FINAL TEMPLATE.
It is a production-ready framework for building autonomous agents with security-first architecture.

## Core Principles

### Documentation Enforcement
- **CLAUDE.md**: Hot memory rules and project identity (this file)
- **ADRs**: Architecture Decision Records (docs/adr/) — all major decisions logged with rationale
- **JOURNEY.md**: Per-session progress tracking (project-specific)
- **Artifacts**: Committed implementation evidence (Terraform, workflows, code)

### Security Model
- GitHub App tokens (never classic PATs)
- GCP Secret Manager for credential storage
- Explicit secret passing (never secrets:inherit)
- Workload Identity Federation for credential-less GCP access
- Per-secret IAM bindings (least privilege)

### Git Workflow
- NEVER push directly to `main` — branch protection enforced
- ALL changes to `main` MUST go through Pull Request
- Each feature/change gets its own branch
- PRs do not require approving review (solo projects) but must exist

### Evidence Model
- **Currently Proven**: Works now with concrete evidence
- **Historically Proven**: Worked in the past, evidence exists
- **Assumed**: Plausible but no proof
- **Unknown**: Cannot yet determine
- **Needs Validation**: Promising but requires testing
- **Rejected**: Unsafe, failed, obsolete, or not suitable

## Architecture References

### ADR Documents
All major decisions documented in `docs/adr/`:
- **0100**: Migrate to GitHub App tokens (from classic PATs)
- **0101**: Explicit secret passing (eliminate secrets:inherit)
- **0102**: Refactor mcp__github__* dependencies
- **0103**: WIF branch scoping (enhance credential isolation)
- **0104**: External API token handling (HTTP Authorization header)

### Design Specifications
See `docs/architecture/`:
- **template-repo-structure.md**: Directory layout and file organization
- **bootstrap-automation.md**: Initialization workflow and manual gates
- **provider-integration-patterns.md**: Provider-specific setup (GCP, GitHub, Railway, Cloudflare, N8N)
- **journey-format.md**: Session progress tracking format

## Before You Start

1. Review all 5 ADRs in `docs/adr/`
2. Read `docs/architecture/bootstrap-automation.md` completely
3. Ensure GitHub App credentials and GCP setup ready
4. Create JOURNEY.md for your session
5. Set up provider integration following `docs/architecture/provider-integration-patterns.md`

## Environment Assumptions
- Git available and configured
- GitHub CLI optional (use curl + token if unavailable)
- GCP CLI optional (use Terraform/API if unavailable)
- For cloud sessions: network isolation may apply — use offline-first approach

## Output Language
All human-facing explanations must be in clear Hebrew.
Code, file names, commands, and technical identifiers remain in English.

---

**Status**: Alpha (v0.1.0-phase-6-architecture)  
**Last Updated**: 2026-04-28  
**License**: Apache 2.0
