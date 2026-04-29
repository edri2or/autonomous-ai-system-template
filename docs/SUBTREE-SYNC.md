# Documentation Subtree Sync

## Overview

The following directories are **git subtrees** — their source of truth is
`edri2or/claude-builder-pro` (the control plane). Do NOT edit them directly here.

| Directory | Source Branch | Description |
|-----------|---------------|-------------|
| `docs/adr/` | `adr-export` | Architecture Decision Records (ADR-0100 through ADR-0104+) |
| `docs/architecture/` | `arch-export` | Architecture design specifications |

## How Sync Works

1. A change is merged to `main` in `claude-builder-pro` under `docs/adr/` or `docs/architecture/`
2. `export-docs-subtree.yml` runs in the control plane:
   - Runs `git subtree split` to create/update `adr-export` and `arch-export` branches
   - Sends a `repository_dispatch` event (`docs-updated`) to this repo
3. `sync-from-control-plane.yml` receives the event:
   - Runs `git subtree pull` for each directory using `--squash`
   - Commits with a reference to the source commit SHA
   - Pushes directly to `main`

## Rules

- **Never edit** `docs/adr/` or `docs/architecture/` directly in this repo
- Always use `--squash` consistently — mixing squash/non-squash breaks future pulls
- The `SYNC_PAT` secret must be valid in both repositories for sync to work

## Required Secret: `SYNC_PAT`

A Fine-Grained Personal Access Token stored in both repos:

| Repo | Permission needed |
|------|------------------|
| `edri2or/claude-builder-pro` | Contents: Read + Write (for export branch push + dispatch) |
| `edri2or/autonomous-ai-system-template` | Contents: Write (for subtree pull + push) |

## One-Time Migration

Run `initial-subtree-migration.yml` via Actions → workflow_dispatch **once** after
the PR that introduced this file is merged. It:
1. Deletes the pre-existing copied `docs/adr/` and `docs/architecture/`
2. Re-adds them as proper git subtrees from the control plane export branches

After migration, only `sync-from-control-plane.yml` handles ongoing sync.
