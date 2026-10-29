import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "bundled_resources", Path(__file__).with_name("verify-bundled-resources.py")
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class BundledResourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "Resources"
        self.app = self.root / "ListRunner.app"
        self.source.mkdir()
        self.app.mkdir()
        for name in ["bunnings.json", "ingredients.json"]:
            (self.source / name).write_text('{"version":1}')
            (self.app / name).write_text('{"version":1}')

    def test_all_canonical_resources_match(self):
        self.assertEqual(verifier.verify_resources(self.source, self.app), [])

    def test_missing_bunnings_is_reported(self):
        (self.app / "bunnings.json").unlink()
        self.assertIn("Missing bundled resource: bunnings.json", verifier.verify_resources(self.source, self.app))

    def test_changed_resource_is_reported(self):
        (self.app / "ingredients.json").write_text('{"version":2}')
        self.assertIn("Bundled resource differs from canonical file: ingredients.json", verifier.verify_resources(self.source, self.app))

    def test_duplicate_resource_is_reported(self):
        (self.app / "bunnings-v2.json").write_text('{}')
        self.assertIn("Duplicate legacy resource bundled: bunnings-v2.json", verifier.verify_resources(self.source, self.app))

    def test_missing_app_is_reported(self):
        self.assertTrue(verifier.verify_resources(self.source, self.root / "absent.app"))

    def test_empty_canonical_folder_is_reported(self):
        empty = self.root / "Empty"
        empty.mkdir()
        self.assertTrue(verifier.verify_resources(empty, self.app))


if __name__ == "__main__":
    unittest.main()
