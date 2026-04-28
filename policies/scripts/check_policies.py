#!/usr/bin/env python3
"""
check_policies.py
Validates ADR-mandated security policies across the repository.
Called by autonomous-control-plane.yml.
"""
import os
import sys
import glob
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

errors = []
warnings = []


def check_no_secrets_inherit():
    """ADR-0101: No secrets:inherit in any workflow file."""
    for path in glob.glob(f"{ROOT}/.github/workflows/*.yml"):
        with open(path) as f:
            content = f.read()
        if "secrets: inherit" in content:
            errors.append(f"{path}: 'secrets: inherit' found (ADR-0101 violation)")


def check_no_mcp_github_refs():
    """ADR-0102: No mcp__github__ references in any file."""
    for ext in ("*.yml", "*.yaml", "*.sh", "*.py"):
        for path in glob.glob(f"{ROOT}/**/{ext}", recursive=True):
            if ".git" in path:
                continue
            with open(path) as f:
                content = f.read()
            if "mcp__github__" in content:
                errors.append(f"{path}: mcp__github__ reference found (ADR-0102 violation)")


def check_github_app_pattern():
    """ADR-0100: At least one workflow uses create-github-app-token."""
    found = False
    for path in glob.glob(f"{ROOT}/.github/workflows/*.yml"):
        with open(path) as f:
            if "create-github-app-token" in f.read():
                found = True
                break
    if not found:
        errors.append("No workflow uses actions/create-github-app-token (ADR-0100 violation)")


def check_bearer_pattern():
    """ADR-0104: External API calls use Authorization: Bearer, not inline tokens."""
    bad_patterns = [
        r'"API_KEY"\s*:\s*\$\{',
        r'"token"\s*:\s*\$\{secrets\.',
        r"requests\.get\([^)]+secret",
    ]
    for path in glob.glob(f"{ROOT}/scripts/**/*.sh", recursive=True):
        with open(path) as f:
            content = f.read()
        for pattern in bad_patterns:
            if re.search(pattern, content):
                warnings.append(f"{path}: possible inline token (check ADR-0104 compliance)")


def check_wif_branch_scope():
    """ADR-0103: WIF Terraform config includes branch attribute condition."""
    wif_tf = f"{ROOT}/terraform/wif.tf"
    if os.path.exists(wif_tf):
        with open(wif_tf) as f:
            content = f.read()
        if "refs/heads/main" not in content:
            errors.append("terraform/wif.tf missing branch-scoped attribute_condition (ADR-0103)")
    else:
        warnings.append("terraform/wif.tf not found — WIF branch scoping unverifiable")


if __name__ == "__main__":
    check_no_secrets_inherit()
    check_no_mcp_github_refs()
    check_github_app_pattern()
    check_bearer_pattern()
    check_wif_branch_scope()

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  ⚠  {w}")

    if errors:
        print("\nERRORS:")
        for e in errors:
            print(f"  ✗  {e}")
        print(f"\nPolicy check FAILED ({len(errors)} error(s))")
        sys.exit(1)

    print(f"Policy check PASSED (0 errors, {len(warnings)} warnings)")
