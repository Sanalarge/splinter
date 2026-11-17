#!/usr/bin/env python3
import argparse
import json
import re
import subprocess


def api(endpoint, method="GET", data=None):
    command = ["gh", "api", "--method", method, endpoint]
    if data is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(data) if data is not None else None,
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def configure(repository):
    endpoint = f"repos/{repository}"
    repo = api(endpoint)
    if not repo.get("permissions", {}).get("admin"):
        raise PermissionError("Repository administration access is required")
    if repo["private"]:
        raise ValueError("This policy is for a public repository; visibility is never changed automatically")
    api(f"{endpoint}/branches/main")
    api(endpoint, "PATCH", {
        "description": "A lightweight macOS mouse remapper for Apple Silicon and Intel. English and Turkish. Built with SwiftUI.",
        "default_branch": "main", "allow_squash_merge": True,
        "allow_merge_commit": False, "allow_rebase_merge": False,
        "allow_auto_merge": False, "delete_branch_on_merge": True,
        "allow_update_branch": True, "has_wiki": False,
        "security_and_analysis": {
            "secret_scanning": {"status": "enabled"},
            "secret_scanning_push_protection": {"status": "enabled"},
        },
    })
    api(f"{endpoint}/vulnerability-alerts", "PUT")
    api(f"{endpoint}/automated-security-fixes", "PUT")
    api(f"{endpoint}/private-vulnerability-reporting", "PUT")
    api(f"{endpoint}/actions/permissions", "PUT", {"enabled": True, "allowed_actions": "selected"})
    api(f"{endpoint}/actions/permissions/selected-actions", "PUT", {
        "github_owned_allowed": False, "verified_allowed": False,
        "patterns_allowed": ["actions/checkout@*", "actions/upload-artifact@*",
                             "actions/download-artifact@*", "github/codeql-action/*@*"],
    })
    api(f"{endpoint}/actions/permissions/workflow", "PUT", {
        "default_workflow_permissions": "read", "can_approve_pull_request_reviews": False,
    })
    api(f"{endpoint}/actions/permissions/fork-pr-contributor-approval", "PUT", {
        "approval_policy": "all_external_contributors",
    })
    rulesets = api(f"{endpoint}/rulesets?per_page=100")
    main = {
        "name": "Protect main", "target": "branch", "enforcement": "active", "bypass_actors": [],
        "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
        "rules": [
            {"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "required_linear_history"},
            {"type": "pull_request", "parameters": {
                "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": True,
                "require_code_owner_review": False, "require_last_push_approval": False,
                "required_review_thread_resolution": True,
            }},
            {"type": "required_status_checks", "parameters": {
                "strict_required_status_checks_policy": True,
                "required_status_checks": [
                    {"context": "Test and build", "integration_id": 15368},
                    {"context": "Analyze Swift", "integration_id": 15368},
                ],
            }},
        ],
    }
    tags = {
        "name": "Protect releases", "target": "tag", "enforcement": "active", "bypass_actors": [],
        "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
        "rules": [{"type": "deletion"}, {"type": "update"}],
    }
    maintainers = {
        "name": "Maintainer-only main updates", "target": "branch", "enforcement": "active",
        "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
        "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
        "rules": [{"type": "update"}],
    }
    for policy in [main, tags, maintainers]:
        existing = next((item for item in rulesets if item["name"] == policy["name"]), None)
        path = f"{endpoint}/rulesets" + (f"/{existing['id']}" if existing else "")
        api(path, "PUT" if existing else "POST", policy)
    print(f"Configured pull-request protection, release tags, scanning and Actions permissions for {repository}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Apply Splinter's public repository policy using GitHub CLI")
    parser.add_argument("--repo", default="Sanalarge/splinter")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("Expected OWNER/REPOSITORY")
    configure(args.repo)
