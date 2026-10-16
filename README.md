# ADB Dock

A macOS menu bar app that keeps Android **wireless debugging** devices connected over `adb`.

`adb` already auto-connects devices it has paired with, but there is no visibility into *which* device
is up, no way to pair a new device without opening Android Studio, and nothing that notices when adb's
own mDNS client has silently stopped discovering your phone. This is that missing layer: an
approved-device list with live connection state, one-click pairing, and self-recovery.

## Requirements

| | |
|---|---|
| macOS | 13 or later (menu bar app — no Dock icon, no window) |
| adb | Android platform-tools: `brew install android-platform-tools`, or the copy in `~/Library/Android/sdk/platform-tools` |
| Build tools | Xcode command line tools (`swiftc`) |
| Device | Android 11 or later with **Developer options → Wireless debugging** enabled |

The app finds `adb` at `/opt/homebrew/bin/adb`, `/usr/local/bin/adb`, `~/Library/Android/sdk/platform-tools/adb`,
or a login-shell `PATH` lookup — apps launched by `launchd` get a minimal `PATH`, so it never relies on
`which adb` alone. Set `ADB=/path/to/adb` to override the search (useful when the installed
platform-tools has a broken subcommand).

## Build and run

```sh
git clone https://github.com/tripathiamritansh/adbdock.git
cd adbdock
./build.sh --run          # build and launch
./build.sh                # build only
open build/AdbDock.app
```

First launch shows an empty list; add a device below. Quit from the menu (⌘Q).

### Bundle identifier

`build.sh` bakes a bundle identifier into the app, and that same identifier is the LaunchAgent label
used by **Start at login**. The default is `com.example.adbdock`; override it per machine with an
untracked `local.env`:

```sh
echo 'BUNDLE_ID=com.yourname.adbdock' > local.env
```

## Adding a device

Two paths, neither of which needs Android Studio:

**Pair a device this Mac has never seen**

1. On the phone: **Settings → Developer options → Wireless debugging → Pair device with pairing
   code**, and leave that screen open — the device only advertises for pairing while it is showing.
2. Menu bar → **Pair new device…** — or **Pair this device…** on a row that reads *connect failed —
   pair it?* — then type the 6-digit code.

The app waits up to ~7 s for the pairing advertisement to appear, retries the code up to three times
(reopening the phone's screen generates a new code), then attaches the device and adds it to the
approved list.

**Check the address in the dialog.** It comes from an unauthenticated mDNS advertisement, so compare
it with the IP address and port on the phone's screen; if they differ, cancel. When several devices
advertise a pairing service and none matches the device you clicked, the app asks which one to use
rather than guessing.

`adb pair` reports *every* failure as `error: protocol fault (couldn't read status message)` — a wrong
code, an expired pairing screen and an unreachable port are indistinguishable. If it fails twice,
reopen the pairing screen (new code, new port) and try again.

**Attach a device this Mac has already paired** (for example, paired earlier from Android Studio)

Menu bar → **Discovered — not in list** → the device → **Add (already paired)**. This only connects:
pairing is what puts this Mac's key on the device, and it cannot be skipped.

### Why not a QR code?

Android's *Pair device with QR code* screen expects the **host** to run a pairing server and display a
`WIFI:T:ADB;S:…;P:…;;` payload. That pairing server is Android Studio's own code: the adb command line
is client-only (`adb pair HOST[:PORT] [PAIRING CODE]`), and the platform-tools 35.0.2 binary contains
neither the `WIFI:T:ADB` payload marker nor any host-side pairing-server strings — checked with
`grep -a -o -E 'WIFI:T:ADB|pairing_server|_adb-tls-pairing[a-z._]*' $(command -v adb)`. So the 6-digit
screen is the only pairing path a CLI-driven app can use; a QR flow would mean reimplementing adb's
pairing handshake (a security-sensitive protocol) against the phone's scanner.

## Pausing a device

**Pause connection** on a device row is *hands off*, not a disconnect: the adb transport is left
exactly as it is, but ADB Dock stops managing that device — it will not auto-attach it, will not
re-attach it after the phone drops off the network, and will not count it as a reason to restart the
shared adb server. The row shows ⏸ with the connection state preserved, and `state.json` marks it
`"paused": true`.

Use it when you want a live connection you are driving yourself (a long `adb install`, a logcat
session, a scripted test) and you don't want anything else touching it.

### Pause vs Disconnect

| | Pause connection | Disconnect |
|---|---|---|
| the adb transport | **left attached** — `adb devices` still shows it and your own session keeps working | dropped (`adb disconnect`) |
| the app's auto-attach | stopped | stopped too — a bare disconnect would otherwise be undone within ~5 s, so Disconnect pauses as well |
| how it looks | ⏸ paused — connected | ⏸ paused — offline |
| to undo | **Resume connection** (or **Connect now**) | **Connect now** (re-attaches and hands it back to the app) |

`Connect now` always clears the pause: an explicit connect means "manage this device again".

## What the rows mean

| Glyph | State | Meaning |
|---|---|---|
| 🟢 | connected | transport attached; address shown |
| 🟡 | connecting… | advertising on the network, this app is attaching it |
| 🟡 | connect failed — pair it? | advertising, but adb can't attach it — almost always because this Mac has never been paired with that device |
| 🟠 | offline / unauthorized | transport exists but is not usable (accept the prompt on the phone) |
| ⚪ | not on network | not advertising — wireless debugging off, phone off, or a different network |

## Menu

| Item | What it does |
|---|---|
| device row | submenu: **Connect now**, **Disconnect**, **Pause connection** / **Resume connection**, **Pair this device…** (when the connect failed or the transport went stale), **Rename…**, **Remove from list** |
| **+ <model>** (discovered) | submenu: **Add (already paired)**, **Pair this device…** |
| **Pair new device…** (⌘P) | full `adb pair` flow against the advertised pairing service |
| **Refresh now** (⌘R) | re-read adb state immediately |
| **Restart adb server** | `kill-server` + `start-server` — the manual lever when adb's mDNS is wedged |
| **Start at login** | write/remove the LaunchAgent |
| **Reveal devices.json** | show the approved list in Finder |
| footer | adb version and mDNS backend health |
| **Quit ADB Dock** (⌘Q) | |

**⌃⌥⌘A** opens the menu from anywhere — see *If the icon is not visible* below.

## Headless use

```sh
build/AdbDock.app/Contents/MacOS/AdbDock --dump   # snapshot as JSON, exits (no UI, no auto-connect)
build/AdbDock.app/Contents/MacOS/AdbDock --menu   # the status menu as text, exits
```

`--dump` is handy for scripts and for seeing the app's view of the world without clicking. Its output
is the same document the app keeps in `state.json`.

## Files

| Path | Purpose |
|---|---|
| `~/Library/Application Support/AdbDock/devices.json` | approved list (serial, label, last seen) |
| `~/Library/Application Support/AdbDock/state.json` | live snapshot, rewritten on change (≤1/min when idle); includes `lastError` when an attach failed |
| `~/Library/Application Support/AdbDock/app.log` | launch, status-item geometry, auto-connect results, actions, alerts — truncated each launch |
| `~/Library/LaunchAgents/<bundle-id>.plist` | written by **Start at login** |

## If the icon is not visible (notched MacBooks)

On a MacBook with a camera notch, macOS lays status items out around the notch and — when the menu bar
is full — parks the extra ones *behind* it, where they are invisible and unclickable. The app detects
this and says so in `app.log`:

```
statusItem visible=true frame=(1120.0, -33.0, 32.0, 33.0) screen=(0.0, 0.0, 1512.0, 982.0)
screen notch gap x 700.0…900.0
WARNING: status item is behind the notch — press ⌃⌥⌘A to open the menu, or free menu bar space
```

(The numbers are illustrative; the app reads the real geometry at launch.)

Three ways out: press **⌃⌥⌘A** (always works, even when the icon is hidden), ⌘-drag the item out from
behind the notch into a free slot, or free up menu bar space (quit a few menu bar apps) so the layout
stops spilling.

## When adb's own mDNS wedges

Observed behaviour: an adb server started while the phone was **off** the network can stop discovering
it entirely, even after the phone returns with wireless debugging on — `adb mdns services` stays empty
while the system resolver sees the device instantly (`dns-sd -B _adb-tls-connect._tcp`).
`adb kill-server && adb start-server` fixes it immediately. The wedged server reported adb's
`Openscreen` mDNS backend; working servers reported Bonjour.

The app handles this on its own:

- It **forces the Bonjour backend** (`ADB_MDNS_OPENSCREEN=0`) for every adb server it starts, so the
  server uses mDNSResponder rather than adb's own client.
- When adb's mDNS sees nothing, it asks **Bonjour** (`dns-sd`) — the system view of the network. If an
  approved device is advertising there while *nothing at all* is attached, it concludes its adb server
  is the broken part, restarts it (at most once every 5 minutes), logs the reason, and re-attaches.
- **Restart adb server** in the menu does the same thing by hand for the cases the heuristic
  deliberately skips (it will not restart the server while some other device is attached and working,
  so it never kills an in-flight `adb install`).

Exercise the recovery path without waiting for a real wedge:

```sh
ADBDOCK_FAULT_NO_MDNS=1 build/AdbDock.app/Contents/MacOS/AdbDock
# app.log then shows: adb mDNS blind (Bonjour sees <serial>) — restarted adb server: …
```

## Privacy

- **No network calls of its own, no telemetry, no accounts.** The app shells out to `adb` and to the
  system `dns-sd` and reads their output; the only network traffic is whatever `adb` itself does.
- **One exception worth naming:** when adb's own mDNS sees nothing, the app browses the local network
  itself with `dns-sd -B` (mDNS queries on your LAN — local discovery, never an internet connection).
- **One place it runs code of yours:** if none of the known adb locations exist, it falls back to
  `zsh -lc 'command -v adb'`, which sources your shell profile. Set `ADB=/path/to/adb` to skip that.
- **State stays on your machine**, in `~/Library/Application Support/AdbDock/`, created `0700` with
  files written `0600` (serials and LAN addresses are not world-readable).
- **Nothing is uploaded anywhere**, and there is no update check or analytics.
- It is ~1,450 lines of Swift in `Sources/` — small enough to read before you run it.

## Notes and caveats

- **The approved list is bookkeeping, not a firewall.** adb auto-connects any device it has paired
  with; this app decides what it shows and force-attaches — it cannot stop adb from attaching a paired
  device.
- **Device identity is the serial**, not the mDNS name (the random suffix is regenerated each time
  adbd restarts) and not the address (the port changes every time wireless debugging is toggled). The
  app never hardcodes `ip:port`.
- **After a phone reboot** Android turns Wireless debugging off; re-enable it on the phone. Nothing
  host-side can flip that setting — an on-device app with `WRITE_SECURE_SETTINGS` (granted once via
  `adb shell pm grant`) or root can.
- **Removing a device from the list keeps the adb pairing key** (`~/.android/adb_known_hosts.pb`).
- **mDNS needs macOS Local Network permission.** If the menu footer shows `mDNS: unavailable`, grant
  *Local Network* access to ADB Dock in System Settings → Privacy & Security.
- The legacy `adb tcpip 5555` route is a fixed-port alternative that does not need the Wireless
  debugging toggle, but it needs a cable (or a live transport) after each reboot and opens a
  plaintext adb port on the LAN.
- macOS only, and only as good as the `adb` on your `PATH`: platform-tools 35.x is what this was
  developed against.

## Layout

| Path | |
|---|---|
| `Sources/Adb.swift` | process runner, adb discovery, parsers (`mdns services`, `devices -l`), serial extraction, server restart |
| `Sources/Bonjour.swift` | system-resolver discovery (`dns-sd`) used to detect a wedged adb mDNS client |
| `Sources/Engine.swift` | snapshot computation, auto-connect loop, JSON serialisation |
| `Sources/Store.swift` | approved list persistence |
| `Sources/Menu.swift` | status menu construction (+ `--menu` text rendering) |
| `Sources/HotKey.swift` | global hotkey (⌃⌥⌘A) |
| `Sources/Log.swift` | `app.log` writer |
| `Sources/main.swift` | CLI modes, app delegate, actions, LaunchAgent toggle |
| `build.sh` | `swiftc` → `.app` bundle, `Info.plist`, ad-hoc signing |

## License

MIT — see [LICENSE](LICENSE).
