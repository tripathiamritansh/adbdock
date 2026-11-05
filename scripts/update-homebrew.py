#!/usr/bin/env python3
"""Update the cask from the published release's checksum sidecars."""
from pathlib import Path
import re
import sys


def version_tuple(value):
    if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", value):
        raise ValueError("Invalid numeric version")
    return tuple(map(int, value.split("."))) + ((0,) if value.count(".") == 1 else ())


def render(current, version, directory):
    match = re.search(r'^  version "([^"]+)"$', current, re.MULTILINE)
    if not match:
        raise ValueError("Cannot find cask version")
    if version_tuple(version) <= version_tuple(match[1]):
        return current  # A delayed run must never downgrade a newer cask.
    hashes = {}
    for arch in ("arm64", "x86_64"):
        name = f"AdbDock-{version}-{arch}-unsigned.dmg"
        parts = (directory / (name + ".sha256")).read_text().split()
        if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{64}", parts[0]) or parts[1] != name:
            raise ValueError(f"Invalid published checksum for {arch}")
        hashes[arch] = parts[0]
    # Replace only the release metadata block, preserving install/uninstall policy.
    start = current.index("\n", current.index('cask "adbdock" do')) + 1
    end = current.index('  name "ADB Dock"', start)
    metadata = (f'  arch arm: "arm64", intel: "x86_64"\n\n'
                f'  version "{version}"\n'
                f'  sha256 arm:   "{hashes["arm64"]}",\n'
                f'         intel: "{hashes["x86_64"]}"\n\n'
                '  url "https://github.com/tripathiamritansh/adbdock/releases/download/'
                'v#{version}/AdbDock-#{version}-#{arch}-unsigned.dmg"\n')
    return (current[:start] + metadata + current[end:]).replace('  depends_on arch: :arm64\n', '')


if __name__ == "__main__":
    cask = Path("Casks/adbdock.rb")
    cask.write_text(render(cask.read_text(), sys.argv[1], Path(sys.argv[2])))
