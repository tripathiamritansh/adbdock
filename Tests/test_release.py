"""Release automation regressions; no GitHub requests or release mutations."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


policy = load_script("ci-version")
release = load_script("publish-release")
homebrew = load_script("update-homebrew")


class PolicyTests(unittest.TestCase):
    def test_release_scope(self):
        for path in ("Sources/Adb.swift", "Tests/test_release.py", "scripts/package-dmg.sh",
                     ".github/workflows/ci.yml", "VERSION", "build.sh", "docs/INSTALL.txt", "LICENSE"):
            with self.subTest(path=path):
                self.assertTrue(policy.needs_release([path]))
        self.assertFalse(policy.needs_release(["README.md", "docs/USAGE.md", "SECURITY.md",
                                              "Casks/adbdock.rb", ".github/main-ruleset.json"]))

    def test_version_is_stable_across_retries(self):
        self.assertEqual(policy.ci_version("1.1.0", "42"), "1.1.42")
        for base, number in (("v1.1.0", "42"), ("1.1", "42"), ("1.1.0", "0"), ("1.1.0", "1;id")):
            with self.subTest(base=base, number=number), self.assertRaises(ValueError):
                policy.ci_version(base, number)

    def test_event_gating(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            event = Path(directory) / "event.json"
            event.write_text(json.dumps({"before": "a" * 40}))
            for name, ref, paths, expected in (
                ("pull_request", "refs/pull/1/merge", "Sources/Adb.swift\0", False),
                ("workflow_dispatch", "refs/heads/automation/homebrew-v1.1.42", "", False),
                ("workflow_dispatch", "refs/heads/main", "", True),
                ("push", "refs/heads/main", "Casks/adbdock.rb\0", False),
                ("push", "refs/heads/main", "Sources/Adb.swift\0README.md\0", True),
            ):
                with self.subTest(event=name, ref=ref, paths=paths), patch.dict(os.environ, {
                    "GITHUB_RUN_NUMBER": "42", "GITHUB_EVENT_NAME": name, "GITHUB_REF": ref,
                    "GITHUB_EVENT_PATH": str(event), "GITHUB_SHA": "b" * 40, "GITHUB_OUTPUT": str(output),
                }), patch.object(policy.subprocess, "check_output", return_value=paths):
                    output.write_text("")
                    policy.main()
                    expected_version = policy.ci_version((ROOT / "VERSION").read_text().strip(), "42")
                    self.assertEqual(output.read_text(), f"version={expected_version}\npublish={str(expected).lower()}\n")


class ReleaseTests(unittest.TestCase):
    version = "1.1.42"
    commit = "b" * 40
    repository = "example/adbdock"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        for arch in ("arm64", "x86_64"):
            stem = f"AdbDock-{self.version}-{arch}-unsigned"
            dmg = self.directory / f"{stem}.dmg"
            dmg.write_bytes(f"fixture-{arch}".encode())
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            (self.directory / f"{stem}.dmg.sha256").write_text(f"{digest}  {dmg.name}\n")
            (self.directory / f"{stem}.build-info.txt").write_text(
                f"ADB Dock {self.version}\nArchitecture: {arch}\nSource commit: {self.commit}\nSource checkout: clean\n")
        self.files = release.release_files(self.directory, self.version, self.commit)
        self.assets = [{"name": p.name, "size": p.stat().st_size,
                        "digest": "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()} for p in self.files]
        self.draft = {"id": 7, "draft": True, "target_commitish": self.commit, "assets": []}
        self.uploaded = {**self.draft, "assets": self.assets}

    def publish(self):
        release.publish(self.directory, self.version, self.repository, self.commit)

    def test_complete_artifacts(self):
        self.assertEqual(len(self.files), 6)

    def test_tampered_dmg_rejected_before_api(self):
        self.files[0].write_bytes(b"modified")
        with patch.object(release, "api") as api, self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            self.publish()
        api.assert_not_called()

    def test_missing_architecture_rejected(self):
        self.files[3].unlink()
        with self.assertRaisesRegex(ValueError, "Missing or invalid"):
            self.publish()

    def test_dirty_or_wrong_commit_rejected(self):
        info = self.files[2]
        original = info.read_text()
        for text in (original.replace("clean", "dirty"), original.replace(self.commit, "c" * 40)):
            info.write_text(text)
            with self.assertRaisesRegex(ValueError, "provenance mismatch"):
                self.publish()

    def test_publish_only_after_verified_upload(self):
        with patch.object(release, "api", side_effect=[None, None, self.draft, self.uploaded, {}]) as api, \
             patch.object(release.subprocess, "run") as run:
            self.publish()
        self.assertTrue(api.call_args_list[2].kwargs["payload"]["draft"])
        self.assertEqual(api.call_args_list[2].kwargs["payload"]["target_commitish"], self.commit)
        self.assertEqual(api.call_args_list[-1].kwargs["payload"], {"draft": False, "make_latest": "legacy"})
        self.assertIn("--clobber", run.call_args.args[0])

    def test_upload_failure_leaves_draft(self):
        with patch.object(release, "api", side_effect=[None, None, self.draft]) as api, \
             patch.object(release.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "gh")), \
             self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertFalse(any(c.kwargs.get("method") == "PATCH" for c in api.call_args_list))

    def test_bad_remote_digest_leaves_draft(self):
        self.assets[0]["digest"] = "sha256:" + "0" * 64
        with patch.object(release, "api", side_effect=[None, None, self.draft, self.uploaded]) as api, \
             patch.object(release.subprocess, "run"), self.assertRaisesRegex(ValueError, "digest mismatch"):
            self.publish()
        self.assertFalse(any(c.kwargs.get("method") == "PATCH" for c in api.call_args_list))

    def test_published_release_is_not_replaced_on_retry(self):
        published = {**self.uploaded, "draft": False}
        ref = {"object": {"type": "commit", "sha": self.commit}}
        with patch.object(release, "api", side_effect=[published, ref]) as api, \
             patch.object(release.subprocess, "run") as run:
            self.publish()
        run.assert_not_called()
        self.assertEqual(api.call_count, 2)

    def test_existing_tag_cannot_redirect_release(self):
        ref = {"object": {"type": "commit", "sha": "c" * 40}}
        with patch.object(release, "api", side_effect=[None, ref]), \
             patch.object(release.subprocess, "run") as run, self.assertRaisesRegex(ValueError, "Existing tag"):
            self.publish()
        run.assert_not_called()

    def test_same_commit_draft_can_resume(self):
        with patch.object(release, "api", side_effect=[self.draft, None, self.uploaded, {}]) as api, \
             patch.object(release.subprocess, "run"):
            self.publish()
        self.assertFalse(any(c.kwargs.get("method") == "POST" for c in api.call_args_list))

    def test_other_commit_draft_cannot_be_replaced(self):
        self.draft["target_commitish"] = "c" * 40
        with patch.object(release, "api", side_effect=[self.draft, None]), \
             self.assertRaisesRegex(ValueError, "another commit"):
            self.publish()

    def test_cask_uses_both_public_checksums(self):
        current = (ROOT / "Casks/adbdock.rb").read_text()
        # Give the fixture a known older version even after the real cask advances.
        current = re.sub(r'^  version "[^"]+"', '  version "1.0"', current, flags=re.MULTILINE)
        updated = homebrew.render(current, self.version, self.directory)
        self.assertIn('version "1.1.42"', updated)
        self.assertIn('arch arm: "arm64", intel: "x86_64"', updated)
        self.assertNotIn("depends_on arch:", updated)
        for arch in ("arm64", "x86_64"):
            self.assertIn(hashlib.sha256(f"fixture-{arch}".encode()).hexdigest(), updated)
        self.assertIn('depends_on cask: "android-platform-tools"', updated)
        self.assertIn('zap trash: "~/Library/Application Support/AdbDock"', updated)
        self.assertEqual(homebrew.render(updated, "1.1.41", self.directory), updated)
        self.assertEqual(homebrew.render(updated, self.version, self.directory), updated)

    def test_cask_rejects_mismatched_checksum_name(self):
        current = (ROOT / "Casks/adbdock.rb").read_text()
        current = re.sub(r'^  version "[^"]+"', '  version "1.0"', current, flags=re.MULTILINE)
        name = self.directory / f"AdbDock-{self.version}-arm64-unsigned.dmg.sha256"
        name.write_text("0" * 64 + "  wrong.dmg\n")
        with self.assertRaisesRegex(ValueError, "Invalid published checksum"):
            homebrew.render(current, self.version, self.directory)


if __name__ == "__main__":
    unittest.main()
