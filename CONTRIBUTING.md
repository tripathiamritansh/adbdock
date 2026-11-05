# Contributing to ADB Dock

Thanks for helping improve ADB Dock. Useful contributions include clearer docs, reproducible bug
reports, device compatibility reports, and focused fixes to pairing, discovery, or the menu.

## Report a bug or propose a change

Check [existing issues](https://github.com/tripathiamritansh/adbdock/issues) first. For a bug, include:

- What you expected, what happened, and the steps to reproduce it.
- The app release or source commit, macOS version, Mac architecture, and `adb version` output.
- Android version and device model when relevant, plus whether the failure concerns pairing,
  connection, discovery, or login startup.
- Relevant, redacted command output or log excerpts from the [troubleshooting guide](docs/USAGE.md#troubleshooting).

Remove real device serials, LAN addresses, personal labels, and pairing codes before posting. Never
attach adb keys or the contents of `~/.android/`. An empty device list alone does not show whether
pairing or discovery failed; describe the phone's Wireless debugging state too.

For a substantial feature or behavior change, open an issue describing the problem and proposed
approach before investing in an implementation. Keep the project's focus in mind: a small, local
macOS menu bar app for wireless adb management.

## Make a change

1. Fork the repository if you need a place to push, then clone your fork. If you already have a
   checkout, use it and preserve any existing work.
2. Create a branch from an up-to-date `main`, for example `git switch -c fix/discovery-status`.
3. Follow the [development guide](docs/DEVELOPMENT.md) to build and validate. Read the
   [architecture guide](docs/ARCHITECTURE.md) before changing discovery or connection behavior.
4. Keep the change focused and follow nearby Swift style. Update the relevant documentation when
   behavior, setup, or commands change. Keep generated `build/` outputs and machine settings out of commits.
5. Commit using your own Git identity, push your branch, and open a pull request against `main`.

The optional [commit guard](docs/DEVELOPMENT.md#commit-guard) checks a maintainer-specific email.
It is not a contributor setup requirement; do not adopt the maintainer's identity to satisfy it.

## Validate and describe your pull request

Explain the problem, the resulting behavior, and how you checked it. Link a related issue if there is
one. For UI changes, include a screenshot with fictional or redacted device details.

| Change | Relevant checks |
|---|---|
| Documentation | Check commands against the code, relative links and heading anchors, and diagram labels. |
| Shell scripts | Run `bash -n build.sh scripts/package-dmg.sh hooks/pre-commit`, then exercise the affected workflow on macOS. |
| Swift or UI behavior | Build on macOS, verify the signature, run `--dump` and `--menu`, and exercise the changed behavior using the development checklist. |
| Pairing or reconnection | Test with an Android phone on the same network; check pause/disconnect behavior and avoid disrupting other adb work. |
| Packaging | Follow the [release guide](docs/RELEASING.md); report the architecture and checks actually run. |

There is no automated app test suite in this checkout. Record the relevant tool/platform versions,
which checks passed, and anything that failed or was not run. Linux contributors can use the
[portable core typecheck](docs/DEVELOPMENT.md#portable-core-inspection-on-linux), but it does not
validate the macOS app or phone behavior. State that limitation in the pull request when applicable.
