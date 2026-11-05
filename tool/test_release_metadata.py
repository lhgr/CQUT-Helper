"""Exercise release validation against real, isolated Git repositories."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("release_metadata.py").resolve()


class ReleaseMetadataTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "--quiet")
        self.commit_version("1.1.0+9")
        self.git("tag", "v1.1.0")
        self.previous_sha = self.git("rev-parse", "HEAD")
        self.commit_version("1.2.1+10")
        self.git("tag", "v1.2.1")
        self.source_sha = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], cwd=self.root, text=True, stderr=subprocess.PIPE
        ).strip()

    def commit_version(self, version):
        (self.root / "pubspec.yaml").write_text(f"version: {version}\n", encoding="utf-8")
        self.git("add", "pubspec.yaml")
        self.git(
            "-c", "user.name=Release test", "-c", "user.email=release@example.invalid",
            "commit", "--quiet", "-m", "Set fixture version",
        )

    def run_metadata(self, *arguments, **event):
        environment = os.environ.copy()
        environment.update({
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_REF_TYPE": "tag",
            "GITHUB_REF_NAME": "v1.2.1",
            "DISPATCH_TAG_NAME": "",
            "SKIP_RELEASE": "false",
        })
        environment.update(event)
        return subprocess.run(
            [sys.executable, str(SCRIPT), *arguments], cwd=self.root,
            env=environment, capture_output=True, text=True,
        )

    def test_tag_push_outputs_version_and_source(self):
        result = self.run_metadata("--release")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(dict(line.split("=", 1) for line in result.stdout.splitlines()), {
            "build_name": "1.2.1", "build_number": "10",
            "source_sha": self.source_sha, "tag_name": "v1.2.1",
        })

    def test_manual_release_uses_input_even_when_dispatched_from_a_tag(self):
        result = self.run_metadata(
            "--release", GITHUB_EVENT_NAME="workflow_dispatch",
            GITHUB_REF_NAME="v1.1.0", DISPATCH_TAG_NAME="v1.2.1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tag_name=v1.2.1", result.stdout)

    def test_manual_release_rejects_a_different_tag_commit(self):
        self.git("tag", "--force", "v1.2.1", self.previous_sha)
        result = self.run_metadata(
            "--release", GITHUB_EVENT_NAME="workflow_dispatch", DISPATCH_TAG_NAME="v1.2.1",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checked-out source commit", result.stderr)

    def test_manual_release_requires_an_existing_tag(self):
        self.git("tag", "--delete", "v1.2.1")
        result = self.run_metadata(
            "--release", GITHUB_EVENT_NAME="workflow_dispatch", DISPATCH_TAG_NAME="v1.2.1",
        )
        self.assertNotEqual(result.returncode, 0)

    def test_skip_release_allows_a_branch_without_a_tag(self):
        self.git("tag", "--delete", "v1.2.1")
        result = self.run_metadata(
            "--release", GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_REF_TYPE="branch",
            GITHUB_REF_NAME="dev", DISPATCH_TAG_NAME="v1.2.1", SKIP_RELEASE="true",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"source_sha={self.source_sha}", result.stdout)

    def test_skip_release_still_validates_the_version(self):
        result = self.run_metadata(
            "--release", GITHUB_EVENT_NAME="workflow_dispatch",
            DISPATCH_TAG_NAME="v1.2.0", SKIP_RELEASE="true",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("release tag must be v1.2.1", result.stderr)

    def test_equal_previous_build_is_rejected(self):
        self.git("tag", "v1.2.0")
        result = self.run_metadata("--release")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must exceed previous maximum 10", result.stderr)

    def test_historical_prerelease_build_is_checked(self):
        self.commit_version("1.1.5-beta+11")
        self.git("tag", "v1.1.5-beta")
        self.git("checkout", "--quiet", self.source_sha)
        result = self.run_metadata("--release")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must exceed previous maximum 11", result.stderr)

    def test_local_ios_build_needs_no_release_tag(self):
        self.git("tag", "--delete", "v1.2.1")
        result = self.run_metadata("--expected-build-name", "1.2.1", "--expected-build-number", "10")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("tag_name=", result.stdout)

    def test_reusable_ios_build_rejects_a_different_prepared_version(self):
        for arguments in [
            ("--expected-build-name", "1.2.0"),
            ("--expected-build-number", "11"),
        ]:
            with self.subTest(arguments=arguments):
                result = self.run_metadata(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("prepared source", result.stderr)

    def test_native_build_version_must_be_numeric(self):
        (self.root / "pubspec.yaml").write_text("version: 1.2.1-alpha+10\n", encoding="utf-8")
        result = self.run_metadata()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("numeric version", result.stderr)

    def test_unrelated_events_cannot_publish(self):
        result = self.run_metadata("--release", GITHUB_EVENT_NAME="pull_request")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
