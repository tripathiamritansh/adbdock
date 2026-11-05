# Homebrew distribution

ADB Dock is distributed as a cask in this repository's `Casks/` directory. It installs the published
DMG and declares Android Platform-Tools as a dependency. Version 1.0 supports Apple silicon and
macOS 13+; an Intel cask needs a separately built and validated Intel release asset.

## Install

With [Homebrew](https://brew.sh/) installed:

```sh
brew tap tripathiamritansh/adbdock https://github.com/tripathiamritansh/adbdock
brew install --cask tripathiamritansh/adbdock/adbdock
```

The explicit tap URL is required because this repository is named `adbdock`, rather than
`homebrew-adbdock`. Once tapped, fully qualified install commands select this project's cask and
avoid name conflicts. Homebrew versions with tap-trust enforcement trust the selected cask when
you explicitly install it this way.

Open `/Applications/AdbDock.app` and follow [pairing](USAGE.md#adding-a-device). If you already have a
manually installed copy there, quit it and move that app bundle aside before installation. Keep its
data directory to preserve approved devices. Homebrew may install its own Platform-Tools even if adb
already exists elsewhere; check [adb resolution](USAGE.md#how-adb-is-found) if you maintain multiple copies.

The release is **ad-hoc signed and not notarized**. Installing through Brew does not change its
signing status or guarantee Gatekeeper approval. Follow the [installation notes](INSTALL.txt) for
the app-specific macOS approval flow; no quarantine removal or global security changes are needed
in the cask.

The cask still installs v1.0. Security fixes on `main` need a new Mac build and release before they
reach Brew installations; see [release security status](../SECURITY.md#release-status).

## Update or remove

```sh
brew update
brew upgrade --cask tripathiamritansh/adbdock/adbdock
```

The uninstall steps used during an upgrade or reinstall remove the default login LaunchAgent.
Reopen the app and re-enable **Start at login** afterward if desired. Upgrades preserve the approved
device list and adb pairing credentials.

To remove the app while keeping its saved list and logs:

```sh
brew uninstall --cask tripathiamritansh/adbdock/adbdock
```

To also remove ADB Dock's device list, state, and logs, use this instead:

```sh
brew uninstall --cask --zap tripathiamritansh/adbdock/adbdock
```

Neither command revokes phone pairing or deletes `~/.android/`. The cask's cleanup targets the
release's `com.example.adbdock` bundle/LaunchAgent ID; custom source builds using another ID must
disable their own login startup. Homebrew manages dependency cleanup separately.

## Maintain the cask

[`Casks/adbdock.rb`](../Casks/adbdock.rb) points to the immutable v1.0 release URL and records the
DMG's SHA-256. The cask does not build from source or disable macOS security checks.

For each release:

1. Build, package, and validate on the supported Mac architecture using [RELEASING.md](RELEASING.md).
   Publish the DMG, checksum, and original build-info sidecar under a new version tag. Do not replace
   an existing version's asset with different bytes.
2. Download the published DMG and check its companion checksum. Update the cask's `version`,
   `sha256`, and URL pattern if needed. Update the bundle ID and minimum OS only when the artifact changes.
3. Run the style check from this checkout on a Mac with Homebrew:

   ```sh
   brew style Casks/adbdock.rb
   ```

4. Before publishing the cask update, test it from a local tap on an Apple silicon Mac:

   ```sh
   brew tap adbdock/testing "$PWD"
   brew trust --cask adbdock/testing/adbdock
   brew audit --cask --strict adbdock/testing/adbdock
   brew install --cask adbdock/testing/adbdock
   codesign --verify --deep --strict /Applications/AdbDock.app
   open /Applications/AdbDock.app
   ```

   Use a disposable test account without a conflicting installation. Validate first launch,
   adb discovery, pairing, login startup, upgrade/reinstall, uninstall, and optional zap behavior.
   The local tap clones committed files: commit the candidate change before this check. The `trust`
   command is for current Homebrew versions with tap-trust enforcement. Remove the
   test installation and `brew untap adbdock/testing` when finished.
5. Commit and push the verified cask to `main`. Users receive it through `brew update` and
   `brew upgrade`. Record checks that were not run as well as results that passed.

The initial cask passed `brew style`, a strict audit targeting macOS/ARM, and `brew fetch` with
SHA-256 verification on Linux. Native install, launch, upgrade, and removal through Homebrew still
require Mac validation; the DMG's earlier validation is recorded separately in [RELEASING.md](RELEASING.md).

## Official Homebrew catalog

This tap is maintained by the project. A plain `brew install --cask adbdock` on a machine with no
tap requires acceptance into [`Homebrew/homebrew-cask`](https://github.com/Homebrew/homebrew-cask).
That is a separate contribution reviewed by Homebrew's maintainers.

The current unsigned, unnotarized release is not ready for that submission. Prepare a Developer ID
signed and notarized release, verify Gatekeeper acceptance on the latest macOS, and satisfy
Homebrew's [cask requirements](https://docs.brew.sh/Acceptable-Casks) and
[package acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy). Run `brew audit --cask --new`
for the candidate and resolve its findings before opening a Homebrew PR. Publishing this tap does
not imply acceptance into the official catalog.
