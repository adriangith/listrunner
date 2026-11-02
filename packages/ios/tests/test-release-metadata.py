import plistlib
import unittest
from pathlib import Path


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[1] / "ListRunner" / "Info.plist"
        self.info = plistlib.loads(path.read_bytes())

    def test_versions_follow_xcode_settings(self):
        self.assertEqual(self.info["CFBundleShortVersionString"], "$(MARKETING_VERSION)")
        self.assertEqual(self.info["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")

    def test_identity_and_permission_are_preserved(self):
        self.assertEqual(self.info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
        self.assertEqual(self.info["CFBundleDisplayName"], "ListRunner")
        self.assertTrue(self.info["NSRemindersFullAccessUsageDescription"])


if __name__ == "__main__":
    unittest.main()
