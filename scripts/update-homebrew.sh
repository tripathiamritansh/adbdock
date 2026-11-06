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
# A retry incorporates current main and preserves any existing branch edits.
# Push normally: a concurrent update must fail rather than be overwritten.
existing="$(git ls-remote --heads origin "$branch")"
if [ -n "$existing" ]; then
  git fetch origin "refs/heads/$branch"
  git merge --no-edit FETCH_HEAD
fi
git push origin "HEAD:refs/heads/$branch"
if ! pr="$(gh pr list --repo "$GITHUB_REPOSITORY" --head "$branch" --base main --state open --json number --jq '.[0].number // empty')"; then
  echo '::error title=Cannot read Homebrew pull requests::Check the workflow pull-requests permission and repository Actions policy.'
  exit 1
fi
if [ -z "$pr" ]; then
  body="$checksums/pr-body.md"
  cat > "$body" <<EOF
Update the cask to [ADB Dock $APP_VERSION](https://github.com/$GITHUB_REPOSITORY/releases/tag/v$APP_VERSION) with the published Apple silicon and Intel checksums.

The release passed the native CI build, regression tests, CLI smoke tests and DMG verification. Homebrew style passed. Installation, upgrade and physical-device checks still need maintainer validation before merge; see docs/HOMEBREW.md.

This metadata-only merge does not publish another release.
EOF
  if ! gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
    --title "Update Homebrew cask to $APP_VERSION" --body-file "$body" 2>"$checksums/pr-error.txt"; then
    # Put the actual failure in a public annotation; full logs require sign-in.
    python3 - "$checksums/pr-error.txt" <<'PY'
from pathlib import Path
import sys
message = Path(sys.argv[1]).read_text().strip()
message = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print(f'::error title=Homebrew PR creation failed::{message}')
PY
    echo 'Enable Settings > Actions > General > Allow GitHub Actions to create and approve pull requests, then run the Homebrew workflow for this version.' >&2
    echo "Manual PR: https://github.com/$GITHUB_REPOSITORY/compare/main...$branch?expand=1" >&2
    exit 1
  fi
fi
# GITHUB_TOKEN-created PR events do not start another workflow. An explicit
# workflow_dispatch is allowed and supplies the required CI check on this branch.
gh workflow run ci.yml --repo "$GITHUB_REPOSITORY" --ref "$branch"
