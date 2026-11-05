#!/bin/bash
# Run only in the trusted post-release job; never push directly to main.
set -euo pipefail
: "${APP_VERSION:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
branch="automation/homebrew-v${APP_VERSION}"
checksums="$(mktemp -d "$RUNNER_TEMP/adbdock-checksums.XXXXXX")"
trap 'rm -rf "$checksums"' EXIT
# A rerun may rebuild different DMG bytes. Always use the immutable public release.
gh release download "v$APP_VERSION" --repo "$GITHUB_REPOSITORY" \
  --pattern '*.dmg.sha256' --dir "$checksums"
python3 scripts/update-homebrew.py "$APP_VERSION" "$checksums"
if git diff --quiet -- Casks/adbdock.rb; then
  echo 'Cask already has this version or a newer release.'
  exit 0
fi
brew style Casks/adbdock.rb
gh auth setup-git
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git switch -c "$branch"
git add Casks/adbdock.rb
git commit -m "Update Homebrew cask to $APP_VERSION"
# Do not overwrite an existing branch on retries; dispatch/check the existing PR.
if ! git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  git push origin "HEAD:refs/heads/$branch"
fi
pr="$(gh pr list --repo "$GITHUB_REPOSITORY" --head "$branch" --base main --state open --json number --jq '.[0].number // empty')"
if [ -z "$pr" ]; then
  body="$checksums/pr-body.md"
  cat > "$body" <<EOF
Update the cask to [ADB Dock $APP_VERSION](https://github.com/$GITHUB_REPOSITORY/releases/tag/v$APP_VERSION) with the published Apple silicon and Intel checksums.

The release passed the native CI build, regression tests, CLI smoke tests and DMG verification. Homebrew style passed. Installation, upgrade and physical-device checks still need maintainer validation before merge; see docs/HOMEBREW.md.

This metadata-only merge does not publish another release.
EOF
  gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
    --title "Update Homebrew cask to $APP_VERSION" --body-file "$body"
fi
# GITHUB_TOKEN-created PR events do not start another workflow. An explicit
# workflow_dispatch is allowed and supplies the required CI check on this branch.
gh workflow run ci.yml --repo "$GITHUB_REPOSITORY" --ref "$branch"
