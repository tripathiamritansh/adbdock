#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/security-tests/module-cache
swiftc -swift-version 5 -module-cache-path "$PWD/build/security-tests/module-cache" \
  Sources/Adb.swift Sources/Bonjour.swift Tests/SecurityTests.swift \
  -o build/security-tests/security-tests
build/security-tests/security-tests
python3 Tests/test_commit_guard.py
