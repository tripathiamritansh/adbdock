# Packaging an unsigned DMG

ADB Dock 1.0's first downloadable image is for **Apple silicon (`arm64`) only**.
The DMG is unsigned and not notarized. Its app is ad-hoc signed for executable
integrity, without a verified Developer ID. adb is not bundled. See the
[installation notes](INSTALL.txt) for prerequisites and app-specific Gatekeeper guidance.

## Build on a Mac

With macOS 13+ and Apple's Command Line Tools, run from the repository root:

```sh
./scripts/package-dmg.sh
```

The script builds the current Mac's architecture through `build.sh`, stages a copy,
ad-hoc signs it, creates an image, verifies its integrity and read-only mount, checks
the copied binary/plist/install notes/license and Applications shortcut, then ejects
the image. Verified outputs go to ignored `build/release/`:

```text
AdbDock-1.0-arm64-unsigned.dmg
AdbDock-1.0-arm64-unsigned.dmg.sha256
AdbDock-1.0-arm64-unsigned.build-info.txt
```

`./scripts/package-dmg.sh --skip-build` packages an existing `build/AdbDock.app`.
It does not establish that an existing binary matches the current source. Both modes
sign the staged copy; the packaging step leaves the supplied bundle untouched.
An Intel source build is possible on matching hardware, but no Intel release image
has been built or validated for this release. No universal binary is provided.

The image contains only `AdbDock.app`, an `/Applications` shortcut, `INSTALL.txt`,
and `LICENSE`. It contains no adb binary, device data, pairing credentials, or local
configuration. Timestamps can change between builds; byte-for-byte reproducibility
is not claimed. Outputs are replaced only after validation and detachment succeed.
If detachment fails, inspect `hdiutil info` and follow the script's printed detach
command before removing retained temporary files.

## Recorded arm64 validation

The published image has SHA-256:

```text
903ff2389ce7b7a8ac907986325e8365dd3256e676ce4fe3805744533815e877
```

It was built on macOS 15.6.1 (24G90), arm64, with Apple Swift 6.1 in Swift 5
language mode, targeting macOS 13. The local adb installation was Platform-Tools
35.0.2 (protocol 1.0.41). Android 11+ wireless debugging and a shared local network
are required; no new Android hardware-version test was recorded during packaging.

| Check | Result |
|---|---|
| Native build, DMG integrity and read-only mount | Passed |
| Staged/mounted file comparison and Applications shortcut | Passed |
| Strict ad-hoc app signature | Passed; no Developer ID or notarization |
| Install from image, eject, launch installed copy | Passed in an isolated installation |
| Installed `--dump` and `--menu` | Passed with zero approved/discovered devices |
| Menu and antenna visibility | User confirmed shortcut/menu; original screenshot visually inspected. Antenna returned after the user reduced menu-bar crowding. No source fix was made. |
| Real-device pairing/reconnection and login startup | Previously reported as verified by the maintainer; not independently repeated for this packaging run |
| Downloaded/quarantined Gatekeeper flow | Not tested; local launch does not establish download behavior |
| Intel image | Not built or validated |

The README's two approved images are edited and upscaled screenshots. Other
menu-bar icons were removed. The connected view uses fictional device details,
as its caption discloses; a still image is not an end-to-end hardware test.

## Source correspondence

The app's `Sources/`, `build.sh`, and `LICENSE` are unchanged from commit
`bd30de7cb2393322b9e94502ba726ad560c2d9af`. The packaging script and bundled
`INSTALL.txt` match the exact inputs used to generate the tested image. The
release tag includes those inputs plus documentation and approved screenshots;
documentation changes did not rebuild or alter the DMG.

The original build-info sidecar records the base commit, dirty checkout and
`skip-build=true`: the app had just been built, then packaging was retried with
host access after a sandbox mount-tool limitation. Preserve that original record
alongside the checksum rather than rewriting its provenance to the newer docs commit.

## Verify an image

From its download directory:

```sh
shasum -a 256 -c AdbDock-1.0-arm64-unsigned.dmg.sha256
hdiutil verify AdbDock-1.0-arm64-unsigned.dmg
```

Follow [INSTALL.txt](INSTALL.txt), install in a stable location, eject the image,
then open the installed app. A checksum detects changes but does not authenticate
the developer. Do not disable Gatekeeper globally or recursively remove quarantine.
Managed Macs may disallow an override. Keep unrun checks separate from passed checks.
