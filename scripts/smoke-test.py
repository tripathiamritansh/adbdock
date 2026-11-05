#!/usr/bin/env python3
"""Exercise the actual macOS app's two CLI modes with a deterministic adb fixture."""
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
binary = root / "build/AdbDock.app/Contents/MacOS/AdbDock"
fixture = root / "Tests/fixtures/adb-empty.sh"
environment = {**os.environ, "ADB": str(fixture)}


def run(mode):
    return subprocess.run([str(binary), mode], env=environment, check=True,
                          text=True, capture_output=True, timeout=45).stdout


snapshot = json.loads(run("--dump"))
assert set(snapshot) >= {"updatedAt", "adbPath", "adbVersion", "mdns", "mdnsSummary",
                         "connectLog", "devices", "discovered"}
assert snapshot["adbPath"] == str(fixture)
assert "CI-fixture" in snapshot["adbVersion"]
assert snapshot["devices"] == snapshot["discovered"] == snapshot["connectLog"] == []
menu = run("--menu")
assert "No approved devices yet" in menu and "Pair new device" in menu and "Quit ADB Dock" in menu
print("Passed native --dump JSON and --menu smoke tests (empty-device fixture)")
