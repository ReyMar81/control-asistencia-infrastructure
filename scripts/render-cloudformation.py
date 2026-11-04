#!/usr/bin/env python3
"""Generate CloudFormation user-data from the shared Cloud-Init templates."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "cloudformation" / "template.yaml.tmpl"
TARGET = ROOT / "cloudformation" / "template.yaml"
USER_DATA = ROOT / "cloud-init" / "user-data"


def render_user_data(name: str, substitutions: dict[str, str]) -> str:
    content = (USER_DATA / name).read_text(encoding="utf-8")
    for source, target in substitutions.items():
        content = content.replace("${" + source + "}", "${" + target + "}")
    expected = {
        "backend.yaml.tmpl": {
            "BACKEND_REPO_URL",
            "GIT_BRANCH",
            "DB_USER",
            "DB_PASSWORD",
            "DB_NAME",
            "JWT_SECRET",
            "CLIENT_URL",
            "PORT",
        },
        "frontend.yaml.tmpl": {"FRONTEND_REPO_URL", "GIT_BRANCH", "BACKEND_PRIVATE_IP"},
    }[name]
    expected_targets = {
        "backend.yaml.tmpl": {
            "BackendRepoUrl",
            "GitBranch",
            "DbUser",
            "DbPassword",
            "DbName",
            "JwtSecret",
            "ClientUrl",
            "BackendPort",
        },
        "frontend.yaml.tmpl": {
            "FrontendRepoUrl",
            "GitBranch",
            "BackendInstance.PrivateIp",
        },
    }[name]
    placeholders = re.findall(r"\$\{([A-Za-z0-9_.-]+)\}", content)
    unresolved = sorted(set(placeholders) - expected_targets)
    if any(value in expected for value in unresolved):
        raise ValueError(f"Unresolved Cloud-Init placeholders in {name}: {unresolved}")
    for value in unresolved:
        content = content.replace("${" + value + "}", "${!" + value + "}")
    if any(block not in content for block in ("packages:", "write_files:", "runcmd:")):
        raise ValueError(f"Cloud-Init blocks are incomplete in {name}")
    return "\n".join("            " + line if line else "            " for line in content.splitlines())


def main() -> None:
    template = SOURCE.read_text(encoding="utf-8")
    backend = render_user_data(
        "backend.yaml.tmpl",
        {
            "BACKEND_REPO_URL": "BackendRepoUrl",
            "GIT_BRANCH": "GitBranch",
            "DB_USER": "DbUser",
            "DB_PASSWORD": "DbPassword",
            "DB_NAME": "DbName",
            "JWT_SECRET": "JwtSecret",
            "CLIENT_URL": "ClientUrl",
            "PORT": "BackendPort",
        },
    )
    frontend = render_user_data(
        "frontend.yaml.tmpl",
        {
            "FRONTEND_REPO_URL": "FrontendRepoUrl",
            "GIT_BRANCH": "GitBranch",
            "BACKEND_PRIVATE_IP": "BackendInstance.PrivateIp",
        },
    )
    rendered = template.replace("__BACKEND_USER_DATA__", backend).replace(
        "__FRONTEND_USER_DATA__", frontend
    )
    if "__BACKEND_USER_DATA__" in rendered or "__FRONTEND_USER_DATA__" in rendered:
        raise ValueError("Cloud-Init markers were not fully replaced")
    TARGET.write_text(rendered, encoding="utf-8")
    print(f"Generated {TARGET}")


if __name__ == "__main__":
    main()
