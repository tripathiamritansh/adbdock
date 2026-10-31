#!/bin/bash
# Build a native macOS app and package an unsigned, unnotarized disk image.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/package-dmg.sh [--skip-build]

Build with ./build.sh, then create a verified unsigned DMG in build/release/.
--skip-build  Package the existing build/AdbDock.app instead of rebuilding it.
The staged app is ad-hoc signed; no Developer ID or notarization is used.
USAGE
}

skip_build=false
case "${1:-}" in
  '') ;;
  --skip-build) skip_build=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi

if [ "$(uname -s)" != Darwin ]; then
  echo 'DMG packaging requires macOS, Apple Command Line Tools, and hdiutil.' >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
for tool in hdiutil ditto codesign shasum xcrun plutil; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
xcrun --find lipo >/dev/null
if [ "$skip_build" = false ]; then
  xcrun --find swiftc >/dev/null
  ./build.sh
fi

app=build/AdbDock.app
plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/AdbDock"
[ -f "$plist" ] && [ -x "$binary" ] || { echo 'Missing app bundle; run ./build.sh first.' >&2; exit 1; }
plutil -lint "$plist" >/dev/null
version="$(plutil -extract CFBundleShortVersionString raw -o - "$plist")"
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$plist")"
executable="$(plutil -extract CFBundleExecutable raw -o - "$plist")"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || [ "$executable" != AdbDock ] || [ -z "$bundle_id" ]; then
  echo 'Unexpected app metadata: expected a numeric version, bundle ID, and AdbDock executable.' >&2
  exit 1
fi
arch="$(xcrun lipo -archs "$binary")"
case "$arch" in
  arm64|x86_64) ;;
  *) echo "Expected one arm64 or x86_64 executable architecture, got: $arch" >&2; exit 1 ;;
esac

mkdir -p build/release
work_dir="$(mktemp -d "$repo_root/build/dmg-work.XXXXXX")"
mount_dir="$work_dir/mount"
mounted=false
cleanup() {
  if [ "$mounted" = true ]; then
    # Preserve the mount directory if macOS still has the image attached.
    if ! hdiutil detach "$mount_dir"; then
      echo "Could not confirm image detachment. Inspect with hdiutil info; if mounted, run: hdiutil detach '$mount_dir'" >&2
      echo "Temporary files retained in: $work_dir" >&2
      return
    fi
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT
stage="$work_dir/staging"
mkdir -p "$stage" "$mount_dir"
ditto "$app" "$stage/AdbDock.app"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL.txt "$stage/INSTALL.txt"
cp LICENSE "$stage/LICENSE"

# Keep local executable integrity without claiming a verified developer identity.
# Re-sign only the staged copy; --skip-build never modifies the supplied bundle.
codesign --force --sign - "$stage/AdbDock.app"
codesign --verify --deep --strict "$stage/AdbDock.app"
signature="$(codesign --display --verbose=2 "$stage/AdbDock.app" 2>&1)"
if [[ "$signature" != *'Signature=adhoc'* ]]; then
  echo 'Expected an ad-hoc signature on the staged app.' >&2
  exit 1
fi

name="AdbDock-${version}-${arch}-unsigned"
dmg="$work_dir/$name.dmg"
hdiutil create -volname "ADB Dock $version" -srcfolder "$stage" -format UDZO -fs HFS+ "$dmg"
hdiutil verify "$dmg"
# Attach can fail after partial setup; attempt detachment even on that error path.
mounted=true
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg"
[ -x "$mount_dir/AdbDock.app/Contents/MacOS/AdbDock" ]
[ -f "$mount_dir/INSTALL.txt" ] && [ -f "$mount_dir/LICENSE" ]
[ -L "$mount_dir/Applications" ] && [ "$(readlink "$mount_dir/Applications")" = /Applications ]
cmp "$stage/AdbDock.app/Contents/MacOS/AdbDock" "$mount_dir/AdbDock.app/Contents/MacOS/AdbDock"
cmp "$stage/AdbDock.app/Contents/Info.plist" "$mount_dir/AdbDock.app/Contents/Info.plist"
cmp docs/INSTALL.txt "$mount_dir/INSTALL.txt"
cmp LICENSE "$mount_dir/LICENSE"
codesign --verify --deep --strict "$mount_dir/AdbDock.app"
hdiutil detach "$mount_dir"
mounted=false

source_commit=unknown
source_state='unknown (no Git metadata)'
if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_commit="$(git rev-parse HEAD)"
  source_state=clean
  if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then source_state=dirty; fi
fi
cat > "$work_dir/$name.build-info.txt" <<INFO
ADB Dock $version
Architecture: $arch
Bundle identifier: $bundle_id
Source commit: $source_commit
Source checkout: $source_state
Build mode: skip-build=$skip_build
Packaging host: $(sw_vers -productVersion) ($(uname -m))
Packaged UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
DMG: unsigned, not notarized
App: ad-hoc signed, no Developer ID
Validated: DMG integrity; read-only mount; app signature; binary/plist copy; install notes; Applications link
Not validated by packaging: Gatekeeper approval, UI, login startup, device pairing or reconnection
INFO
(
  cd "$work_dir"
  shasum -a 256 "$name.dmg" > "$name.dmg.sha256"
  shasum -a 256 -c "$name.dmg.sha256"
)
# Do not replace prior release outputs until image verification and detachment pass.
mv "$dmg" "build/release/$name.dmg"
mv "$work_dir/$name.dmg.sha256" "build/release/$name.dmg.sha256"
mv "$work_dir/$name.build-info.txt" "build/release/$name.build-info.txt"
echo "Created build/release/$name.dmg (unsigned, not notarized; $arch)"
