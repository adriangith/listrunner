import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cloud_archive", BASE / "tests/verify-cloud-archive.py")
archive_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive_module)


class CloudCITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def archive(self):
        archive = self.root / "Build with spaces.xcarchive"
        app = archive / "Products/Applications/ListRunner.app"
        app.mkdir(parents=True)
        resources = BASE / "ListRunner/Resources"
        for resource in [*resources.glob("*.json"), *resources.glob("*.js")]:
            shutil.copy(resource, app / resource.name)
        info = {"CFBundleIdentifier": "com.adrianzafir.listrunner",
                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "3"}
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        return archive, app, info

    def hook(self, **variables):
        env = {key: value for key, value in os.environ.items() if not key.startswith("CI_")}
        env.update(variables)
        return subprocess.run(["bash", str(BASE / "ci_scripts/ci_post_xcodebuild.sh")],
                              cwd=self.root, env=env, capture_output=True, text=True)

    def test_archive_records_exact_source_and_resources_not_upload_success(self):
        archive, _, _ = self.archive()
        result = self.hook(CI_XCODEBUILD_ACTION="archive", CI_XCODEBUILD_EXIT_CODE="0",
                           CI_ARCHIVE_PATH=str(archive), CI_BUILD_NUMBER="3")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads(result.stdout)
        self.assertEqual(len(manifest["sourceCommit"]), 40)
        self.assertEqual(manifest["archiveBuild"], "3")
        self.assertEqual(manifest["canonicalResources"], len(list((BASE / "ListRunner/Resources").glob("*.json"))))
        self.assertEqual(manifest["automationResources"], len(list((BASE / "ListRunner/Resources").glob("*.js"))))
        self.assertIn("not-upload-confirmation", manifest["status"])

    def test_failed_xcodebuild_cannot_report_archive_success(self):
        result = self.hook(CI_XCODEBUILD_ACTION="archive", CI_XCODEBUILD_EXIT_CODE="65")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_xcodebuild_result_fails_closed(self):
        self.assertNotEqual(self.hook(CI_XCODEBUILD_ACTION="archive").returncode, 0)

    def test_non_archive_action_does_not_require_archive(self):
        self.assertEqual(self.hook(CI_XCODEBUILD_ACTION="build", CI_XCODEBUILD_EXIT_CODE="0").returncode, 0)

    def test_successful_archive_action_requires_archive_path(self):
        self.assertNotEqual(self.hook(CI_XCODEBUILD_ACTION="archive", CI_XCODEBUILD_EXIT_CODE="0").returncode, 0)

    def test_missing_resource_fails_archive(self):
        archive, app, _ = self.archive()
        (app / "bunnings.json").unlink()
        with self.assertRaisesRegex(ValueError, "Missing bundled resource"):
            archive_module.audit(archive)

    def test_wrong_app_identity_fails_archive(self):
        archive, app, info = self.archive()
        info["CFBundleIdentifier"] = "unrelated.app"
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            archive_module.audit(archive)

    def test_unresolved_build_fails_archive(self):
        archive, app, info = self.archive()
        info["CFBundleVersion"] = "$(CURRENT_PROJECT_VERSION)"
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "version/build"):
            archive_module.audit(archive)

    def test_missing_or_ambiguous_archive_fails(self):
        with self.assertRaisesRegex(ValueError, "exactly one"):
            archive_module.audit(self.root / "absent")
        archive, app, _ = self.archive()
        (app.parent / "Other.app").mkdir()
        with self.assertRaisesRegex(ValueError, "exactly one"):
            archive_module.audit(archive)

    def test_offline_runner_stops_at_first_failed_check(self):
        # Run the real orchestration script with tool stubs, never native/live tests.
        base = self.root / "ios"
        (base / "tests").mkdir(parents=True)
        shutil.copy(BASE / "tests/run-cloud-checks.sh", base / "tests/run-cloud-checks.sh")
        tools = self.root / "bin"
        tools.mkdir()
        log = self.root / "commands.log"
        for name in ["node", "xcrun", "swiftc", "python3"]:
            stub = tools / name
            stub.write_text('#!/bin/bash\necho "$0 $*" >> "$CHECK_LOG"\n' +
                            ('exit 7\n' if name == "python3" else 'exit 0\n'))
            stub.chmod(0o755)
        env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", CHECK_LOG=str(log))
        result = subprocess.run(["bash", str(base / "tests/run-cloud-checks.sh")], env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)
        self.assertNotIn("test-store-expansion.py", log.read_text())
        self.assertNotIn("all cloud offline checks", result.stdout)


if __name__ == "__main__":
    unittest.main()
