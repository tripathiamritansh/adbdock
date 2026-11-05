#!/bin/sh
# Deterministic CLI smoke-test fixture. Never starts a real adb daemon.
case "$*" in
  version) printf 'Android Debug Bridge version CI-fixture\n' ;;
  'devices -l') printf 'List of devices attached\n' ;;
  'mdns services') printf 'List of discovered mdns services\n' ;;
  'mdns check') printf 'mdns discovery CI-fixture\n' ;;
  *) printf 'Unexpected adb command in smoke test\n' >&2; exit 64 ;;
esac
