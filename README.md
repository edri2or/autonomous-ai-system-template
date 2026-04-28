# Autonomous AI System Template

Production-ready framework for building autonomous agents with proven security, infrastructure, and skill management patterns.

## Quick Start

This template provides:
- **Security-first architecture** with GitHub App tokens, GCP Secret Manager, and explicit secret passing
- **Infrastructure automation** with Terraform for GCP, Railway, and Cloudflare
- **Skills framework** with 70+ reusable, portable skills
- **Documentation enforcement** across 4 layers (CLAUDE.md, ADRs, JOURNEY.md, artifacts)
- **Bootstrap automation** for initializing new autonomous agent projects

## What's Inside

```
├── docs/
│   ├── adr/           # Architecture Decision Records (0100-0104)
│   └── architecture/  # Design specifications and patterns
├── .claude/           # Claude Code agent definitions
├── CLAUDE.md          # Project instructions and hot memory
└── README.md          # This file
```

## Getting Started

1. **Review the architecture**: Start with `docs/architecture/template-repo-structure.md`
2. **Understand the security model**: Read `docs/adr/` (all 5 ADRs)
3. **Plan your deployment**: Use `docs/architecture/bootstrap-automation.md`
4. **Configure providers**: Follow `docs/architecture/provider-integration-patterns.md`

## Architecture Decisions

All major decisions are documented in Architecture Decision Records:

- **ADR-0100**: Migrate to GitHub App tokens (from classic PATs)
- **ADR-0101**: Explicit secret passing (eliminate secrets:inherit)
- **ADR-0102**: Refactor mcp__github__* dependencies
- **ADR-0103**: WIF branch scoping (enhance credential isolation)
- **ADR-0104**: External API token handling (HTTP Authorization header pattern)

## Provider Integration

This template supports:
- **Required**: GitHub (OAuth + App tokens), GCP (Workload Identity Federation + Secret Manager)
- **Optional**: Railway, Cloudflare, N8N, External APIs (OpenRouter, Linear, Telegram)

## Next Steps

1. Fork or clone this template
2. Update `CLAUDE.md` with project-specific instructions
3. Follow the bootstrap automation workflow
4. Run provider validation gates during deployment

---

**Status**: Alpha (v0.1.0)  
**License**: Apache 2.0
