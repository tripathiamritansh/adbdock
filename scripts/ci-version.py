#!/usr/bin/env python3
"""Compute an immutable CI version and whether this main push needs a release."""
import json
import os
from pathlib import Path
import re
import subprocess


def needs_release(paths):
    return any(p.startswith(("Sources/", "Tests/", "scripts/", ".github/workflows/"))
               or p in {"build.sh", "VERSION", "docs/INSTALL.txt", "LICENSE"} for p in paths)


def ci_version(base, number):
    if not re.fullmatch(r"\d+\.\d+\.\d+", base) or not re.fullmatch(r"[1-9]\d*", number):
        raise ValueError("Invalid VERSION or workflow run number")
    return f"{base.rsplit('.', 1)[0]}.{number}"


def main():
    version = ci_version(Path("VERSION").read_text().strip(), os.environ["GITHUB_RUN_NUMBER"])
    event_name = os.environ["GITHUB_EVENT_NAME"]
    publish = False
    if os.environ["GITHUB_REF"] == "refs/heads/main":
        if event_name == "workflow_dispatch":
            publish = True
        elif event_name == "push":
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
            before = event["before"]
            after = os.environ["GITHUB_SHA"]
            if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (before, after)):
                raise ValueError("Invalid commit SHA")
            if before == "0" * 40:
                publish = True
            else:
                paths = subprocess.check_output(
                    ["git", "diff", "--name-only", "-z", before, after], text=True).split("\0")
                publish = needs_release(paths)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"version={version}\npublish={str(publish).lower()}\n")


if __name__ == "__main__":
    main()
