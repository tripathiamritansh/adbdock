# Developing ADB Dock

Start with the [README's prerequisites and setup](../README.md#quick-start). The application needs
macOS 13+ and Apple's Command Line Tools; installing a Linux Swift compiler does not provide AppKit,
Carbon, or the macOS SDK.

For your first contribution, read [CONTRIBUTING.md](../CONTRIBUTING.md). The
[architecture guide](ARCHITECTURE.md) explains the refresh and recovery flow; the
[user guide](USAGE.md) covers configuration and diagnostics.

## Build and run

From the repository root on a Mac:

```sh
./build.sh
./build.sh --run
```

The second command rebuilds and relaunches the build output. Quit an installed Applications copy
first. `build.sh` compiles all `Sources/*.swift` with optimization, Swift 5 language mode, and a
`<current-architecture>-apple-macos13.0` target. It writes `build/AdbDock.app`, generates `Info.plist`,
and attempts ad-hoc signing. It does not create a universal binary, installer, Developer ID signature,
or notarized distribution. A signing failure currently prints a warning rather than failing the build;
check signing separately when validating an app artifact.

For an unsigned DMG, use [`scripts/package-dmg.sh`](../scripts/package-dmg.sh) after following the
[packaging guide](RELEASING.md). That script requires a valid ad-hoc signature on its staged copy and
verifies the image before saving release outputs. CI packages both architectures; the original v1.0 image was arm64 only. See each release's assets and notes.

`VERSION` supplies the local app version; `APP_VERSION=1.2.0 ./build.sh` overrides it.
The script recreates the output bundle. Do not keep hand-edited files there. Per-machine `BUNDLE_ID`
belongs in the gitignored `local.env`; see [bundle configuration](USAGE.md#start-at-login-and-bundle-identifier).
The script sources that file as shell code. It is not read by the running app. There is no package
manifest, dependency lockfile, or package-install step.

## Source layout

| File | Responsibility |
|---|---|
| [`Sources/Adb.swift`](../Sources/Adb.swift) | adb resolution, bounded subprocess runner, mDNS/transport parsing, pairing and connection commands. |
| [`Sources/Bonjour.swift`](../Sources/Bonjour.swift) | Bounded macOS `dns-sd` browse used for discovery recovery. |
| [`Sources/Engine.swift`](../Sources/Engine.swift) | Snapshots, connection retries, recovery conditions, and JSON serialization. |
| [`Sources/Store.swift`](../Sources/Store.swift) | Approved devices, tolerant JSON decoding, locking, and local persistence. |
| [`Sources/Menu.swift`](../Sources/Menu.swift) | Menu construction and text rendering. |
| [`Sources/HotKey.swift`](../Sources/HotKey.swift) | Carbon global shortcut registration. |
| [`Sources/Log.swift`](../Sources/Log.swift) | Local log writer. |
| [`Sources/main.swift`](../Sources/main.swift) | CLI modes, app delegate, menu actions, pairing dialogs, state writes, and LaunchAgent management. |
| [`build.sh`](../build.sh) | Compilation, app bundle metadata, signing attempt, and optional relaunch. |

## Validation

Run the portable security regressions with Swift and Python 3 installed:

```sh
./scripts/test-security.sh
python3 -B -m unittest discover -s Tests -p 'test_release.py' -v
```

These exercise pairing-code handling, device selection, real subprocess pipes/timeouts, the
commit guard, and release/cask failure handling using temporary fixtures. They need no phone or installed adb. Every PR also runs native builds, CLI smoke tests, signature and DMG checks on Apple silicon and Intel
in [GitHub Actions](../.github/workflows/ci.yml). There is no automated GUI/device suite. Run the following checks on a Mac and record macOS, architecture, Swift,
Platform-Tools, and Android versions. Portable checks do not replace app and physical-device checks.

### Build and command-line modes

From the repository root:

```sh
xcrun swiftc --version
adb version
bash -n build.sh scripts/package-dmg.sh hooks/pre-commit
./build.sh
codesign --verify --deep --strict build/AdbDock.app
build/AdbDock.app/Contents/MacOS/AdbDock --dump
build/AdbDock.app/Contents/MacOS/AdbDock --menu
open build/AdbDock.app
```

Confirm `--dump` emits valid JSON with the [documented fields](USAGE.md#command-line-snapshots)
and `--menu` emits the expected menu. These modes initialize AppKit, invoke adb, and can update
approved devices' last-seen metadata; run them in a macOS user session. They do not run the app's
automatic connection loop. The app bundle's `--dump` and `--menu` modes are not usable Linux
substitutes for the GUI.

For deterministic CLI validation on a fresh test account, `python3 scripts/smoke-test.py` uses an
empty-device adb fixture. It expects an empty approved-device list; it never starts a real adb daemon.

### App and device behavior

- Verify an initial empty approved list, menu opening, the global shortcut, and clean quit. Check
  `app.log` if the shortcut conflicts or the item is hidden by the menu bar/notch.
- Pair a test phone using its current 6-digit code, confirming the dialog address matches the phone.
  Check `adb devices -l` and the row after pairing; pairing success and attach success are separate.
- Add an already-paired phone, rename it, restart the app, and confirm the saved entry persists.
- Toggle Wireless debugging off/on and verify the app updates the row and attempts reconnection when
  the service returns. Ports and mDNS suffixes may change. Check unauthorized/offline behavior too.
- Pause a connected device and confirm the app leaves its transport attached. Disconnect a device
  and confirm the saved pause flag. Resume or use **Connect now** on a disconnected row. Distinguish
  the app's actions from adb's own independent auto-connect behavior.
- Verify **Remove from list** removes the saved entry while leaving pairing intact.
- Enable **Start at login** from the final app location, confirm the LaunchAgent's path, and test an
  actual logout/login. Disable it afterward if it was enabled only for this check.
- Check the support directory/file permissions and redact device information in any shared output.

Use a test device and finish other adb jobs before testing a server restart: the daemon is shared.
Intel and Apple silicon builds must be validated on the corresponding hardware before claiming both
were tested. CI uses one native runner per architecture; physical-device tests still need a person.

### Exercise the discovery-recovery condition

Quit other ADB Dock copies first. Use an approved, unpaused test device that macOS Bonjour can see,
with no transport in the `device` state and no other adb work in progress. Run from the checkout:

```sh
ADBDOCK_FAULT_NO_MDNS=1 build/AdbDock.app/Contents/MacOS/AdbDock
```

The flag makes the engine ignore adb's discovered services. It does not fabricate Bonjour results,
disable adb's own auto-connects, or bypass the other recovery conditions. After at least three empty
refreshes, look in `app.log` for `adb mDNS blind (Bonjour sees ...) — restarted adb server: ...`.
Recovery is limited to once per five minutes, skips while an interactive operation is marked busy,
and skips when any transport reports `device`. An empty phone list alone cannot validate this path.
Quit the fault-injected process and relaunch normally after the check.

## Portable core inspection on Linux

The Foundation-based files can be typechecked separately with a compatible Linux Swift toolchain.
From the repository root, keeping the module cache in the ignored build directory:

```sh
mkdir -p build/module-cache
swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" -typecheck \
  Sources/Adb.swift Sources/Bonjour.swift Sources/Engine.swift Sources/Store.swift Sources/Log.swift
```

This checks only the portable source subset. It does not run the app, invoke macOS `dns-sd`, validate
GUI behavior, or test phone pairing. Existing concurrency diagnostics in `Adb.swift` are warnings in
the project's Swift 5 language mode; moving to Swift 6 language mode requires separate code work.

## Commit guard

[`hooks/pre-commit`](../hooks/pre-commit) is a maintainer-specific guard. It requires the published
maintainer email in both Git configuration and any author/committer email overrides, and scans staged
added content for selected credential patterns. It is not a general secret scanner or a guarantee
against publishing sensitive data.

For the maintainer, enable it from the repository root:

```sh
git config --local core.hooksPath "$PWD/hooks"
```

Enabling it overrides any global `core.hooksPath` for this checkout. Contributors should use their
own Git identity and leave this optional maintainer guard unconfigured. The hook also accepts extra
regex patterns in gitignored `hooks/local-patterns`; keep real device identifiers and addresses out
of tracked files, screenshots, and issue reports.
