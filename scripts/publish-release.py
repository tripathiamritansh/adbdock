#!/usr/bin/env python3
"""Publish only complete, checksum-verified artifacts from this trusted main run."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def api(path, *, method="GET", payload=None, missing_ok=False):
    command = ["gh", "api", "--method", method, path]
    if payload is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True)
    if result.returncode:
        if missing_ok and "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def release_files(directory, version, commit):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid version")
    files = []
    for arch in ("arm64", "x86_64"):
        name = f"AdbDock-{version}-{arch}-unsigned"
        dmg = directory / f"{name}.dmg"
        checksum = directory / f"{name}.dmg.sha256"
        info = directory / f"{name}.build-info.txt"
        for path in (dmg, checksum, info):
            if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
                raise ValueError(f"Missing or invalid asset: {path.name}")
        expected = hashlib.sha256(dmg.read_bytes()).hexdigest()
        if checksum.read_text().strip().split() != [expected, dmg.name]:
            raise ValueError(f"Checksum mismatch: {dmg.name}")
        metadata = info.read_text().splitlines()
        for line in (f"ADB Dock {version}", f"Architecture: {arch}", f"Source commit: {commit}",
                     "Source checkout: clean"):
            if line not in metadata:
                raise ValueError(f"Build provenance mismatch: {info.name}")
        files.extend((dmg, checksum, info))
    return files


def publish(directory, version, repository, commit):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid commit")
    files = release_files(directory, version, commit)
    tag = f"v{version}"
    base = f"repos/{repository}"
    release = api(f"{base}/releases/tags/{tag}", missing_ok=True)
    ref = api(f"{base}/git/ref/tags/{tag}", missing_ok=True)
    if ref and (ref["object"]["type"] != "commit" or ref["object"]["sha"] != commit):
        raise ValueError("Existing tag does not point to this commit")
    names = {p.name for p in files}
    if release:
        if release["target_commitish"] != commit:
            raise ValueError("Existing release targets another commit; refusing to replace it")
        if not release["draft"]:
            if not ref:
                raise ValueError("Published release is missing its tag")
            if names != {asset["name"] for asset in release["assets"]}:
                raise ValueError("Published release has unexpected or missing assets")
            print(f"{tag} already published for this commit; assets left unchanged")
            return
        if not {asset["name"] for asset in release["assets"]} <= names:
            raise ValueError("Draft has unexpected assets; inspect it before retrying")
    else:
        # Explicitly target the tested commit, even if main has moved during the build.
        notes = (f"Source commit: {commit}\n\n"
                 "Native Apple silicon and Intel builds. CI passed the regression tests, "
                 "empty-device CLI smoke tests, strict ad-hoc signature verification, and "
                 "DMG checksum/integrity/read-only-mount checks.\n\n"
                 "DMGs are unsigned and not notarized; apps are ad-hoc signed. "
                 "Real-phone pairing, login startup, GUI interaction, and downloaded-app "
                 "Gatekeeper approval still require manual validation. adb is installed separately.\n\n"
                 "Homebrew updates arrive through a separate pull request. See docs/INSTALL.txt "
                 "and docs/RELEASING.md in the repository for installation and validation details.")
        release = api(f"{base}/releases", method="POST", payload={
            "tag_name": tag, "target_commitish": commit, "name": f"ADB Dock {version}",
            "body": notes, "draft": True, "prerelease": False})
    # Replacing assets is allowed only while this same-commit release remains a draft.
    subprocess.run(["gh", "release", "upload", tag, *map(str, files), "--clobber",
                    "--repo", repository], check=True)
    uploaded = api(f"{base}/releases/{release['id']}")
    if not uploaded["draft"] or names != {asset["name"] for asset in uploaded["assets"]}:
        raise ValueError("Draft changed or assets are incomplete; refusing to publish")
    for asset in uploaded["assets"]:
        path = directory / asset["name"]
        if asset["size"] != path.stat().st_size:
            raise ValueError("Uploaded asset size mismatch")
        if asset.get("digest") != "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError("Uploaded asset digest mismatch")
    api(f"{base}/releases/{release['id']}", method="PATCH",
        payload={"draft": False, "make_latest": "legacy"})
    print(f"Published {tag} for {commit}")


if __name__ == "__main__":
    publish(Path(sys.argv[1]), os.environ["APP_VERSION"],
            os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"])
