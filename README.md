# ADB Dock

**Android wireless debugging in your Mac's menu bar.**

ADB Dock is a macOS menu bar app for seeing which Android devices are connected, pairing new devices
with a code, and keeping your approved devices attached over `adb`. No Android Studio is required.

`adb` already supports pairing and automatic connections. ADB Dock adds a device list with live
status, menu actions, and recovery for a specific failure: adb stops discovering devices that macOS
Bonjour can still see. It runs as a menu bar item, with no Dock icon or main window.

- **See connection state:** connected, advertising, offline, unauthorized, or absent.
- **Pair from the menu:** enter the phone's 6-digit wireless debugging code.
- **Reconnect approved devices:** attempt connections when they advertise on the local network.
- **Pause management per device:** leave an existing transport alone while you use it yourself.
- **Recover discovery:** compare adb's view with Bonjour and conditionally restart a stalled server.
- **Keep it local:** no accounts, telemetry, analytics, or update checks. MIT licensed.

[Get started](#quick-start) · [Pair a device](#adding-a-device) ·
[Troubleshooting](#troubleshooting) · [Development](docs/DEVELOPMENT.md)

## Screenshots

![ADB Dock's macOS menu with no approved or discovered devices](docs/images/adbdock-empty-state.png)

Empty state, before adding a device. Edited and upscaled screenshot; other menu-bar icons removed.

![ADB Dock's macOS menu showing a connected device with example details](docs/images/adbdock-connected.png)

Connected-device view. Edited and upscaled screenshot; other menu-bar icons removed.
**Device details replaced with examples.** “Android Phone” and `192.0.2.10:5555` are fictional details.

## Requirements

| Requirement | Details |
|---|---|
| Mac | macOS 13 or later; Apple silicon or Intel. The build targets the Mac's current architecture. |
| Build tools | Xcode Command Line Tools, including `swiftc`, and Git. Needed to build/package from source, not to run a prebuilt app. |
| adb | Android SDK Platform-Tools. The project was originally developed against platform-tools 35.x. |
| Android device | Android 11 or later with **Developer options → Wireless debugging** enabled. |
| Network | Mac and phone on the same local network, with mDNS discovery and device connections allowed. Guest Wi-Fi/client isolation can block them. |

The full application, including its command-line modes, requires macOS and Apple's frameworks.
Linux and Windows are not supported app platforms. No USB cable or Android Studio is needed for the
wireless pairing flow.

## Install from an unsigned DMG

When a release includes DMG assets, find them on the project's
[Releases page](https://github.com/tripathiamritansh/adbdock/releases). Choose `arm64` for Apple silicon
or `x86_64` for Intel. If no DMG is listed, use the source-build instructions below. adb is a separate
prerequisite and is **not included** in the image; install Android SDK Platform-Tools through your
Android SDK or `brew install --cask android-platform-tools`.

1. Download the DMG and its matching `.dmg.sha256` file from the same trusted release. In their download
   directory, run `shasum -a 256 -c <filename>.dmg.sha256`, replacing the filename with the actual one.
2. Open the DMG, quit any existing ADB Dock copy, and drag `AdbDock.app` to the **Applications** shortcut.
   Use `~/Applications` instead if you do not have permission to install in `/Applications`.
3. Eject the DMG and open the installed app. Enable **Start at login** only from this final location.

These images are **unsigned and not notarized**. The app inside is ad-hoc signed for executable
integrity, without a verified Developer ID. Gatekeeper can block a downloaded copy. If you trust its
source, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway** for that
specific app when offered, following the confirmation prompt. Available controls can vary with macOS
version and device policy. Do not disable Gatekeeper globally or remove quarantine recursively.
Treat malware or damaged-app warnings as reasons to stop and investigate, rather than routine approval.
A checksum detects file changes; it does not authenticate the developer or replace notarization.

A paid Apple Developer membership is not required for this unsigned distribution workflow. The DMG
is a container, not a notarization or security approval. See the [included installation notes](docs/INSTALL.txt)
and [packaging guide](docs/RELEASING.md) for details.

## Quick start

Build from source on your Mac. Install Apple's Command Line Tools if needed, then wait for their
installer to finish:

```sh
xcode-select --install
```

Install adb with [Homebrew](https://brew.sh/) if you do not already have it through the Android SDK:

```sh
brew install --cask android-platform-tools
```

Verify the tools, clone, and build:

```sh
xcrun swiftc --version
adb version
git clone https://github.com/tripathiamritansh/adbdock.git
cd adbdock
./build.sh
open build/AdbDock.app
```

The output is `build/AdbDock.app`. Look for the antenna icon in the menu bar. Your approved list starts
empty; devices adb already sees can appear under **Discovered — not in list**. Follow
[Adding a device](#adding-a-device) next. Quit with **Quit ADB Dock** in the menu.

The build script uses `swiftc` directly in Swift 5 language mode. There are no third-party Swift
libraries or package-install steps; adb is a separate required tool. The script attempts ad-hoc signing
for local use. This is not a Developer ID signing or notarization workflow.

### Optional: keep a copy in Applications

Quit any running copy first, then run these commands from the checkout:

```sh
mkdir -p "$HOME/Applications"
ditto build/AdbDock.app "$HOME/Applications/AdbDock.app"
open "$HOME/Applications/AdbDock.app"
```

Choose a stable app location before enabling **Start at login**. Avoid running a build copy and an
installed copy at the same time: they use the same saved device list and shared adb server.

### How adb is found

The app checks an executable `ADB` environment override first, then these locations:

1. `/opt/homebrew/bin/adb`
2. `/usr/local/bin/adb`
3. `~/Library/Android/sdk/platform-tools/adb`
4. A login-shell lookup with `zsh -lc 'command -v adb'`

Finder and login launches may have a minimal `PATH`. To diagnose a custom installation, quit the app
and launch its executable directly from Terminal with an absolute path:

```sh
ADB=/absolute/path/to/adb build/AdbDock.app/Contents/MacOS/AdbDock
```

That override applies to this launch. It is not saved by **Start at login**. For normal login use,
install adb in one of the supported locations or make it discoverable by the login-shell lookup.

## Adding a device

### Pair a device this Mac has never paired with

1. Connect the Mac and phone to the same local network. Enable **Developer options → Wireless
   debugging** on the phone; Android's exact labels may vary by manufacturer.
2. Open **Pair device with pairing code** on the phone and leave that screen open.
3. Open ADB Dock → **Pair new device…**.
4. **Compare the IP address and port in the Mac dialog with the phone's pairing screen.** Cancel if
   they differ. Enter the current 6-digit code and choose **Pair**.
5. After successful pairing, the app adds the device to its approved list and attempts to attach it.
   If the connection service is not available yet, it will retry when the device advertises.

The dialog offers up to three pairing attempts. Reopening the phone's pairing screen changes the code
and may change the port. Pair one phone at a time when possible: **Pair new device…** initially uses
the first pairing advertisement it finds. A device row's **Pair this device…** tries to match that
device; if it cannot and several candidates remain, it offers an address chooser. Always check the
address, including after a retry, because mDNS advertisements are unauthenticated.

Pairing and connecting are separate operations. A **Paired** message does not guarantee an immediately
usable transport; check the device's row or `adb devices -l` afterward.

### Add a device already paired with this Mac

Choose **Discovered — not in list → device → Add (already paired)**. Devices paired earlier using adb
or Android Studio can use this path. Adding a row does not authorize a new Mac on the phone. If the
connection fails because pairing is missing, use **Pair new device…** or **Pair this device…**.

### QR pairing

ADB Dock implements the pairing-code flow through `adb pair`. It does not implement Android Studio's
QR-code pairing flow; use **Pair device with pairing code** on the phone.

## Device controls and status

The app normally refreshes about every five seconds; adb operations can make a refresh take longer.
Automatic connection attempts are throttled per device: at least 20 seconds apart initially, then
five minutes apart after three consecutive failures. It leaves an unauthorized transport for you to
resolve on the phone.

| Row appearance | Meaning |
|---|---|
| Green dot + address | adb reports a usable transport. The address may also be `USB` or `wireless`. |
| Yellow dot + **connecting…** | A connection service is advertising, but no transport is attached yet. |
| Yellow dot + **connect failed — pair it?** | An automatic attach failed. Missing pairing is one possible cause; check network access too. |
| Orange dot + **offline** / **unauthorized** | A transport exists but is unusable. Check the phone for an authorization prompt. |
| Hollow dot + **not on network** | Neither a matching transport nor a connection advertisement is visible. |
| **⏸ paused — …** | ADB Dock has stopped managing this device; its underlying connection state is still shown. |

### Pause, disconnect, and resume

| Action | Effect |
|---|---|
| **Pause connection** | Stops ADB Dock's reconnect attempts and excludes this device as a reason for automatic server recovery. Leaves the adb transport as it is. |
| **Disconnect** | Requests `adb disconnect` and pauses ADB Dock's management of the device. |
| **Resume connection** | Re-enables ADB Dock's management; connection attempts follow the normal refresh and retry rules. |
| **Connect now** | Clears pause and attempts a connection if the device is advertising. Available when the row is not connected. |
| **Remove from list** | Removes ADB Dock's saved entry. Keeps adb's pairing credentials. |

**The approved list and pause controls govern ADB Dock, not adb's own auto-connect behavior.** adb may
still attach a previously paired device independently. Removing, pausing, or disconnecting a row does
not revoke the phone's trust in this Mac. Revoke pairing through the phone's wireless debugging
settings when needed. Manual **Restart adb server** affects the shared server and all its transports,
including paused devices; avoid it during an install, logcat session, or other adb work.

### Other menu actions

| Item | What it does |
|---|---|
| **Rename…** | Changes the saved label for an approved device. |
| **Pair new device…** (⌘P) | Opens the pairing-code flow. |
| **Refresh now** (⌘R) | Requests a refresh, unless one is already running. |
| **Restart adb server** | Runs `adb kill-server` followed by `adb start-server`. |
| **Start at login** | Creates or removes a per-user LaunchAgent pointing to this app's current location. |
| **Reveal devices.json** | Reveals the approved-list file in Finder. |
| Footer | Shows the adb protocol version and a summary of `adb mdns check`. |
| **Quit ADB Dock** (⌘Q) | Quits the app; does not stop adb or disconnect its devices. |

**⌃⌥⌘A** (Control–Option–Command–A) opens the menu globally when the shortcut registers successfully.

## Start at login and bundle identifier

Launch the app from its chosen location, then enable **Start at login**. The LaunchAgent stores an
absolute executable path. If you move the app, disable login startup from the old location first,
move it, then re-enable it from the new location.

The default bundle identifier and LaunchAgent label are `com.example.adbdock`. To choose your own,
add this line to a gitignored `local.env` in the checkout **before building**:

```sh
BUNDLE_ID=com.yourname.adbdock
```

`local.env` is sourced as shell code by `build.sh`; use only configuration you trust. It is build-time
configuration, not a runtime environment file. If you change the identifier after enabling login
startup, disable the old LaunchAgent first to avoid leaving a second startup entry.

## Command-line snapshots

From the checkout on macOS:

```sh
build/AdbDock.app/Contents/MacOS/AdbDock --dump
build/AdbDock.app/Contents/MacOS/AdbDock --menu
```

`--dump` prints a fresh JSON snapshot. `--menu` prints the menu as text. Both exit without starting the
menu bar refresh loop, auto-connecting devices, or running automatic server recovery. They still
initialize AppKit and invoke adb, which can start its shared daemon and perform its own auto-connects;
these are not Linux/headless-server entry points. Snapshot collection can update saved last-seen
metadata for approved devices.

The JSON has the same structure as `state.json`: `updatedAt`, `adbPath`, `adbVersion`, `mdns`,
`mdnsSummary`, `connectLog`, `devices`, and `discovered`. Per-device details include identity, status,
and optional transport/address/error fields; `paused` is included when true. A fresh `--dump` can differ
from the running app's saved snapshot, including its transient error history.

## Troubleshooting

### adb not found or a build fails

Run `adb version` and `xcrun swiftc --version` in Terminal. Install the missing prerequisite from
[Quick start](#quick-start), and check the app's adb search locations. A working Terminal `PATH` alone
does not establish that a Finder-launched app can find the same binary. If `swiftc` reports missing
Apple frameworks or a macOS standard library, make sure you are building on macOS with Apple's tools.

### No device in pairing mode, or pairing fails

Keep the phone's **Pair device with pairing code** screen open. Check both devices' network, guest
Wi-Fi/client isolation, and any firewall rules blocking local discovery or device connections. On
macOS versions that ask for Local Network access, allow it for the relevant app/tool; review denied
access in **System Settings → Privacy & Security → Local Network**, where available.

The phone's pairing port and connection port are different. Generic errors such as
`protocol fault (couldn't read status message)` can have several causes, including an expired code or
an unreachable pairing service. Reopen the pairing screen, start the pairing flow again, and compare
the newly advertised address before entering the new code. After a reboot or network change, check
whether Wireless debugging is still enabled; ADB Dock does not enable it remotely.

### Connected before, but no longer discovered

Inspect the local adb view:

```sh
adb devices -l
adb mdns check
adb mdns services
```

On macOS, compare it with Bonjour's view (press Control-C to stop browsing):

```sh
dns-sd -B _adb-tls-connect._tcp
```

ADB Dock passes `ADB_MDNS_OPENSCREEN=0` to adb subprocesses to request the Bonjour backend on versions
that support it. This does not reconfigure an already-running server; backend behavior depends on the
installed platform-tools version. An `ok` footer is a summary of command output, not proof that a
particular phone is reachable.

When adb reports no services, the app also browses with macOS `dns-sd`. After at least three empty
refreshes, it may restart adb if Bonjour sees an approved, unpaused device, no transport is in the
`device` state, no interactive operation is marked busy, and the five-minute recovery cooldown has
elapsed. This is a recovery heuristic, not a guarantee for every discovery failure. Manual **Restart
adb server** is available after you have finished other adb work.

### Menu icon hidden or shortcut does not work

On a crowded or notched menu bar, try **⌃⌥⌘A**, free up menu bar space, or move visible status items with
Command-drag. The app logs status-item geometry and warns when it can identify an item behind the
notch. If the shortcut conflicts with another app, `app.log` records a hotkey registration failure.

### Start at login stops working

Check that the app still exists at the location used when startup was enabled. Disable and re-enable
**Start at login** from the intended copy, and inspect `app.log` for LaunchAgent errors. Keep only one
copy configured to start. Changing the bundle identifier also changes the LaunchAgent label.

## Local files and privacy

| Path | Purpose |
|---|---|
| `~/Library/Application Support/AdbDock/devices.json` | Approved devices, labels, pause state, and saved last-seen metadata. |
| `~/Library/Application Support/AdbDock/state.json` | Live JSON snapshot written by the menu bar app after refreshes; includes transient errors when present. |
| `~/Library/Application Support/AdbDock/app.log` | Launch, geometry, connection results, actions, and alerts. Truncated at app launch. |
| `~/Library/LaunchAgents/<bundle-id>.plist` | Login startup entry, created only when enabled. |

The snapshot's timestamp changes on each refresh, so `state.json` can be rewritten about every five
seconds even when device state is unchanged. Device identity is derived from the serial, rather than
relying on a stable mDNS suffix or connection port.

ADB Dock uses local subprocesses (`adb` and macOS `dns-sd`) for device traffic and LAN discovery. It
has no account system, telemetry, analytics, upload service, or update check. adb separately maintains
its keys and paired hosts under `~/.android/`; ADB Dock does not remove those credentials.

The app requests `0700` permissions for its support directory and `0600` for its device, state, and
log files. They contain device identifiers, labels, addresses, and diagnostic details: redact them
before sharing. The fallback adb lookup starts a login shell, which can execute your shell profile;
an explicit executable `ADB` override avoids that lookup.

## Update or uninstall

To update a source build, quit the app, update your checkout, run `./build.sh`, and launch the new
bundle. If you use an Applications copy, replace that copy with the newly built bundle before
relaunching. Keep the same app path and bundle identifier to retain the login configuration. Device
data lives outside the bundle and survives a rebuild.

To uninstall, disable **Start at login**, quit the app, and remove the app bundle. Optionally remove
`~/Library/Application Support/AdbDock/` to delete ADB Dock's local data. This does not uninstall adb,
stop its server, or revoke pairing on the phone.

## Development

See [the development guide](docs/DEVELOPMENT.md) for source layout, build details, manual validation,
and the discovery-recovery test hook, and the [packaging guide](docs/RELEASING.md) for unsigned DMGs.

### Commit guard

From the checkout, enable the repository's existing guard with:

```sh
git config --local core.hooksPath "$PWD/hooks"
```

This overrides a global hooks path for this repository. The guard checks the maintainer's published
commit identity and staged secret patterns, plus optional gitignored `hooks/local-patterns`. External
contributors should read [the guard's scope](docs/DEVELOPMENT.md#commit-guard) before enabling it;
do not impersonate the maintainer to satisfy the identity check.

## License

[MIT](LICENSE).
