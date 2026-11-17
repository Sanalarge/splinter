import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[1] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="splinter-version-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Test User")
        self.git("config", "user.email", "test@example.invalid")
        (self.root / "VERSION").write_text("1.2.0\n")
        self.commit("Initial release")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL).strip()

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "--allow-empty", "-m", message)

    def test_initial_version(self):
        result = release.version_for(self.root)
        self.assertEqual((result["version"], result["build"]), ("1.2.0", "1"))

    def test_push_increments_patch_without_bump_commit(self):
        self.commit("Fix receiver detection")
        self.assertEqual(release.version_for(self.root)["version"], "1.2.1")

    def test_parallel_runs_do_not_depend_on_tag_timing(self):
        self.commit("First change")
        first = release.version_for(self.root)
        self.commit("Second change")
        before = release.version_for(self.root)
        self.git("tag", first["tag"], first["commit"])
        after = release.version_for(self.root)
        self.assertEqual(before, after)
        self.assertEqual(after["version"], "1.2.2")

    def test_published_commit_is_idempotent(self):
        first = release.version_for(self.root)
        self.git("tag", first["tag"])
        self.assertEqual(release.version_for(self.root), first)

    def test_tag_collision_fails(self):
        self.git("tag", "v1.2.1")
        self.commit("Next change")
        with self.assertRaisesRegex(ValueError, "another commit"):
            release.version_for(self.root)

    def test_new_release_line(self):
        self.git("tag", "v1.2.0")
        self.commit("Patch")
        (self.root / "VERSION").write_text("1.3.0\n")
        self.commit("Start next minor release")
        self.assertEqual(release.version_for(self.root)["version"], "1.3.0")

    def test_cannot_move_version_backwards(self):
        self.git("tag", "v1.2.0")
        (self.root / "VERSION").write_text("1.1.0\n")
        self.commit("Invalid release line")
        with self.assertRaisesRegex(ValueError, "advance"):
            release.version_for(self.root)

    def test_uncommitted_version_rejected(self):
        (self.root / "VERSION").write_text("2.0.0\n")
        with self.assertRaisesRegex(ValueError, "Commit VERSION"):
            release.version_for(self.root)

    def test_invalid_semver_rejected(self):
        for version in ("latest", "1.2", "1.2.3-beta", "01.2.3", "1.2.3\nextra"):
            with self.subTest(version=version):
                (self.root / "VERSION").write_text(version)
                with self.assertRaises(ValueError):
                    release.version_for(self.root)

    def test_merge_uses_first_parent_distance(self):
        self.git("checkout", "-b", "feature")
        self.commit("Work one")
        self.commit("Work two")
        self.git("checkout", "main")
        self.git("merge", "--no-ff", "feature", "-m", "Merge feature")
        self.assertEqual(release.version_for(self.root)["version"], "1.2.1")

    def publish_fixture(self, existing=None, missing=False):
        assets = self.root / "dist"
        assets.mkdir(exist_ok=True)
        if not missing:
            (assets / "Splinter-1.2.0-universal.zip").write_bytes(b"package")
            (assets / "SHA256SUMS").write_text("checksum")
        calls = []
        original = subprocess.run

        def command(args, **kwargs):
            if args[0] != "gh":
                return original(args, **kwargs)
            calls.append(args)
            if "--jq" in args:
                return subprocess.CompletedProcess(args, 0, stdout="42\n", stderr="")
            if "api" in args and "--method" not in args:
                return subprocess.CompletedProcess(args, 0 if existing else 1,
                                                   stdout=json.dumps(existing) if existing else "",
                                                   stderr="" if existing else "HTTP 404")
            return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

        environment = {"GITHUB_REPOSITORY": "owner/project", "GITHUB_REF": "refs/heads/main",
                       "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": self.git("rev-parse", "HEAD")}
        with patch.object(release, "ROOT", self.root), patch.dict(os.environ, environment), patch.object(subprocess, "run", side_effect=command):
            release.publish(assets)
        return calls

    def test_release_uploads_before_publishing(self):
        calls = self.publish_fixture()
        create = next(i for i, c in enumerate(calls) if c[1:3] == ["release", "create"])
        upload = next(i for i, c in enumerate(calls) if c[1:3] == ["release", "upload"])
        publish = next(i for i, c in enumerate(calls) if "draft=false" in c)
        self.assertLess(create, upload)
        self.assertLess(upload, publish)
        self.assertIn("--draft", calls[create])
        self.assertIn(self.git("rev-parse", "HEAD"), calls[create])

    def test_existing_release_is_not_modified(self):
        calls = self.publish_fixture(existing={"draft": False})
        self.assertEqual(len(calls), 1)

    def test_retry_resumes_draft_release(self):
        calls = self.publish_fixture(existing={"draft": True})
        self.assertFalse(any(c[1:3] == ["release", "create"] for c in calls))
        self.assertTrue(any("draft=false" in c for c in calls))

    def test_missing_asset_does_not_create_release(self):
        with self.assertRaisesRegex(ValueError, "Missing release asset"):
            self.publish_fixture(missing=True)

    def test_other_branches_cannot_publish(self):
        with patch.object(release, "ROOT", self.root), patch.dict(os.environ, {
            "GITHUB_REPOSITORY": "owner/project", "GITHUB_REF": "refs/heads/feature", "GITHUB_EVENT_NAME": "push"
        }), patch.object(subprocess, "run", wraps=subprocess.run) as command:
            with self.assertRaisesRegex(ValueError, "main-branch"):
                release.publish(self.root)
            self.assertFalse(any(c.args[0][0] == "gh" for c in command.call_args_list))

    def test_different_commit_cannot_publish(self):
        with patch.object(release, "ROOT", self.root), patch.dict(os.environ, {
            "GITHUB_REPOSITORY": "owner/project", "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": "0" * 40
        }):
            with self.assertRaisesRegex(ValueError, "triggering commit"):
                release.publish(self.root)


if __name__ == "__main__":
    unittest.main()
