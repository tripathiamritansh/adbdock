"""Exercise Homebrew PR failure/retry against a local Git remote and fake GitHub CLI."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HomebrewRetryTests(unittest.TestCase):
    def git(self, directory, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=directory, text=True,
                                       stderr=subprocess.PIPE).strip()

    def test_denied_pr_can_retry_without_replacing_release_or_branch_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            remote = base / "remote.git"
            seed = base / "seed"
            bin_dir = base / "bin"
            bin_dir.mkdir()
            self.git(base, "init", "--bare", "--initial-branch=main", str(remote))
            self.git(base, "clone", str(remote), str(seed))
            self.git(seed, "config", "user.name", "Test fixture")
            self.git(seed, "config", "user.email", "fixture@users.noreply.github.com")
            (seed / "Casks").mkdir()
            cask = (ROOT / "Casks/adbdock.rb").read_text()
            cask = re.sub(r'^  version "[^"]+"', '  version "1.0"', cask, flags=re.MULTILINE)
            (seed / "Casks/adbdock.rb").write_text(cask)
            (seed / "scripts").mkdir()
            for name in ("update-homebrew.py", "update-homebrew.sh"):
                shutil.copyfile(ROOT / "scripts" / name, seed / "scripts" / name)
            self.git(seed, "add", ".")
            self.git(seed, "commit", "-m", "Fixture")
            self.git(seed, "push", "origin", "main")
            original_main = self.git(remote, "rev-parse", "main")
            (bin_dir / "brew").write_text('#!/bin/sh\n[ "$*" = "style Casks/adbdock.rb" ]\n')
            (bin_dir / "gh").write_text(textwrap.dedent('''\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import sys
                args = sys.argv[1:]
                base = Path(os.environ["ADBDOCK_TEST_DIR"])
                with (base / "gh-calls").open("a") as log:
                    log.write(" ".join(args) + "\\n")
                if args[:2] == ["release", "download"]:
                    directory = Path(args[args.index("--dir") + 1])
                    for arch, digest in (("arm64", "a" * 64), ("x86_64", "b" * 64)):
                        name = f"AdbDock-1.1.1-{arch}-unsigned.dmg"
                        (directory / (name + ".sha256")).write_text(f"{digest}  {name}\\n")
                elif args[:2] == ["auth", "setup-git"]:
                    pass
                elif args[:2] == ["pr", "list"]:
                    if (base / "pr-created").exists():
                        print("1")
                elif args[:2] == ["pr", "create"]:
                    if not (base / "allow-pr").exists():
                        print("GitHub Actions is not permitted to create or approve pull requests (createPullRequest)", file=sys.stderr)
                        sys.exit(1)
                    (base / "pr-created").touch()
                elif args[:2] == ["workflow", "run"]:
                    (base / "ci-dispatched").touch()
                else:
                    raise SystemExit("Unexpected GitHub mutation: " + repr(args))
            '''))
            for path in bin_dir.iterdir():
                path.chmod(0o755)
            environment = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
                           "APP_VERSION": "1.1.1", "GITHUB_REPOSITORY": "fixture/adbdock",
                           "RUNNER_TEMP": str(base), "ADBDOCK_TEST_DIR": str(base)}
            first = subprocess.run(["bash", "scripts/update-homebrew.sh"], cwd=seed,
                                   env=environment, text=True, capture_output=True, timeout=30)
            self.assertEqual(first.returncode, 1, first.stdout + first.stderr)
            self.assertIn("::error title=Homebrew PR creation failed::GitHub Actions is not permitted", first.stdout)
            self.assertIn("Allow GitHub Actions to create and approve pull requests", first.stderr)
            self.assertFalse((base / "ci-dispatched").exists())
            branch = "automation/homebrew-v1.1.1"
            self.git(remote, "rev-parse", branch)  # The candidate survives the failed PR.
            self.assertEqual(self.git(remote, "rev-parse", "main"), original_main)

            # Simulate a maintainer's branch edit and a newer main before retrying.
            (seed / "branch-note.txt").write_text("Preserve this review note.\n")
            self.git(seed, "add", "branch-note.txt")
            self.git(seed, "commit", "-m", "Review note")
            self.git(seed, "push", "origin", branch)
            review_head = self.git(remote, "rev-parse", branch)
            self.git(seed, "switch", "main")
            (seed / "main-note.txt").write_text("New main content.\n")
            self.git(seed, "add", "main-note.txt")
            self.git(seed, "commit", "-m", "New main")
            self.git(seed, "push", "origin", "main")
            current_main = self.git(remote, "rev-parse", "main")
            retry = base / "retry"
            self.git(base, "clone", str(remote), str(retry))
            (base / "allow-pr").touch()
            result = subprocess.run(["bash", "scripts/update-homebrew.sh"], cwd=retry,
                                    env=environment, text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((base / "ci-dispatched").exists())
            self.assertTrue((base / "pr-created").exists())
            self.assertEqual(self.git(remote, "rev-parse", "main"), current_main)
            self.git(remote, "merge-base", "--is-ancestor", review_head, branch)
            self.git(remote, "merge-base", "--is-ancestor", current_main, branch)
            self.assertEqual(self.git(remote, "show", f"{branch}:branch-note.txt"), "Preserve this review note.")
            calls = (base / "gh-calls").read_text()
            self.assertNotIn("release upload", calls)
            self.assertNotIn("release create", calls)


if __name__ == "__main__":
    unittest.main()
