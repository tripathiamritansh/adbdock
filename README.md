# ADB Wireless

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
`which adb` alone.

## Build and run

```sh
git clone https://github.com/<you>/adb-wireless.git
cd adb-wireless
./build.sh --run          # build and launch
./build.sh                # build only
open build/ADBWireless.app
```

First launch shows an empty list; add a device below. Quit from the menu (⌘Q).

### Bundle identifier

`build.sh` bakes a bundle identifier into the app, and that same identifier is the LaunchAgent label
used by **Start at login**. The default is `com.example.ADBWireless`; override it per machine with an
untracked `local.env`:

```sh
echo 'BUNDLE_ID=com.yourname.adbwireless' > local.env
```

## Adding a device

1. On the phone: **Settings → Developer options → Wireless debugging → Pair device with pairing
   code** (leave that screen open).
2. Menu bar → **Pair new device…** → type the 6-digit code.

The device is paired, connected, and appended to the approved list. Devices that are *already* paired
(for example, paired earlier from Android Studio) appear under **Discovered — not in list** with a
one-click **+ Add**.

## What the rows mean

| Glyph | State | Meaning |
|---|---|---|
| 🟢 | connected | transport attached; address shown |
| 🟡 | connecting… | advertising on the network, this app is attaching it |
| 🟠 | offline / unauthorized | transport exists but is not usable (accept the prompt on the phone) |
| ⚪ | not on network | not advertising — wireless debugging off, phone off, or a different network |

## Menu

| Item | What it does |
|---|---|
| device row | submenu: **Connect now**, **Disconnect**, **Rename…**, **Remove from list** |
| **+ Add "…"** | add a device that is already paired |
| **Pair new device…** (⌘P) | full `adb pair` flow against the advertised pairing service |
| **Refresh now** (⌘R) | re-read adb state immediately |
| **Restart adb server** | `kill-server` + `start-server` — the manual lever when adb's mDNS is wedged |
| **Start at login** | write/remove the LaunchAgent |
| **Reveal devices.json** | show the approved list in Finder |
| footer | adb version and mDNS backend health |
| **Quit ADB Wireless** (⌘Q) | |

**⌃⌥⌘A** opens the menu from anywhere — see *If the icon is not visible* below.

## Headless use

```sh
build/ADBWireless.app/Contents/MacOS/ADBWireless --dump   # snapshot as JSON, exits (no UI, no auto-connect)
build/ADBWireless.app/Contents/MacOS/ADBWireless --menu   # the status menu as text, exits
```

`--dump` is handy for scripts and for seeing the app's view of the world without clicking. Its output
is the same document the app keeps in `state.json`.

## Files

| Path | Purpose |
|---|---|
| `~/Library/Application Support/ADBWireless/devices.json` | approved list (serial, label, last seen) |
| `~/Library/Application Support/ADBWireless/state.json` | live snapshot, rewritten on change (≤1/min when idle) |
| `~/Library/Application Support/ADBWireless/app.log` | launch, status-item geometry, auto-connect results, actions, alerts — truncated each launch |
| `~/Library/LaunchAgents/<bundle-id>.plist` | written by **Start at login** |

## If the icon is not visible (notched MacBooks)

On a MacBook with a camera notch, macOS lays status items out around the notch and — when the menu bar
is full — parks the extra ones *behind* it, where they are invisible and unclickable. The app detects
this and says so in `app.log`:

```
WARNING: status item is behind the notch (notch spans x 771…956) — press ⌃⌥⌘A to open the menu, or free menu bar space
```

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
ADBWIRELESS_FAULT_NO_MDNS=1 build/ADBWireless.app/Contents/MacOS/ADBWireless
# app.log then shows: adb mDNS blind (Bonjour sees <serial>) — restarted adb server: …
```

## Privacy

- **No network calls of its own, no telemetry, no accounts.** The app shells out to `adb` and to the
  system `dns-sd` and reads their output; the only network traffic is whatever `adb` itself does.
- **State stays on your machine**, in `~/Library/Application Support/ADBWireless/`.
- **Nothing is uploaded anywhere**, and there is no update check or analytics.
- It is ~900 lines of Swift in `Sources/` — small enough to read before you run it.

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
  *Local Network* access to ADB Wireless in System Settings → Privacy & Security.
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
