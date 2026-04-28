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
THIS_FILE = os.path.abspath(__file__)

errors = []
warnings = []

# Load each file set once to avoid re-reading the same files per check.
def _load(pattern, recursive=False):
    result = {}
    for path in glob.glob(pattern, recursive=recursive):
        if ".git" in path or os.path.abspath(path) == THIS_FILE:
            continue
        try:
            with open(path) as f:
                result[path] = f.read()
        except OSError:
            pass
    return result

WORKFLOW_FILES = _load(f"{ROOT}/.github/workflows/*.yml")
ALL_SOURCE_FILES = {
    p: c
    for ext in ("*.yml", "*.yaml", "*.sh", "*.py")
    for p, c in _load(f"{ROOT}/**/{ext}", recursive=True).items()
}


def check_no_secrets_inherit():
    """ADR-0101: No secrets:inherit in any workflow file."""
    for path, content in WORKFLOW_FILES.items():
        if "secrets: inherit" in content:
            errors.append(f"{path}: 'secrets: inherit' found (ADR-0101 violation)")


def check_no_mcp_github_refs():
    """ADR-0102: No mcp__github__ references in any tracked file."""
    for path, content in ALL_SOURCE_FILES.items():
        if "mcp__github__" in content:
            errors.append(f"{path}: mcp__github__ reference found (ADR-0102 violation)")


def check_github_app_pattern():
    """ADR-0100: At least one workflow uses create-github-app-token."""
    if not any("create-github-app-token" in c for c in WORKFLOW_FILES.values()):
        errors.append("No workflow uses actions/create-github-app-token (ADR-0100 violation)")


def check_bearer_pattern():
    """ADR-0104: External API calls use Authorization: Bearer, not inline tokens."""
    bad_patterns = [
        r'"API_KEY"\s*:\s*\$\{',
        r'"token"\s*:\s*\$\{secrets\.',
        r"requests\.get\([^)]+secret",
    ]
    for path, content in ALL_SOURCE_FILES.items():
        if not path.endswith(".sh"):
            continue
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
