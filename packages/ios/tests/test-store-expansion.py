"""Linux-compatible checks for the twenty new data-only registrations."""
import json
from pathlib import Path
import re
import unittest
from urllib.parse import quote, unquote, urlsplit

BASE = Path(__file__).resolve().parents[1]
COUNTRIES = {
    "chemistWarehouse": "AU", "priceline": "AU", "officeworks": "AU", "jbHiFi": "AU",
    "targetAU": "AU", "petbarn": "AU", "supercheapAuto": "AU", "bcf": "AU",
    "bunningsNZ": "NZ", "theWarehouse": "NZ", "newWorld": "NZ", "paknsave": "NZ",
    "sainsburys": "GB", "asda": "GB", "morrisons": "GB", "ocado": "GB",
    "waitrose": "GB", "boots": "GB", "walgreens": "US", "cvs": "US",
}


class StoreExpansionTests(unittest.TestCase):
    def test_all_twenty_resources_have_isolated_permanent_identities(self):
        native = (BASE / "ListRunner/StoreConfiguration.swift").read_text()
        self.assertEqual(len(COUNTRIES), 20)
        for number, (store, country) in enumerate(COUNTRIES.items(), 13):
            with self.subTest(store=store):
                data = json.loads((BASE / f"ListRunner/Resources/{store}.json").read_text())
                self.assertEqual(data["id"], store)
                self.assertEqual(data["serviceArea"]["countryCodes"], [country])
                self.assertEqual(data["capabilities"]["cartDetection"], store in {"priceline"})
                self.assertFalse(data["capabilities"]["cartUndo"])
                if data["cart"] is not None:
                    self.assertEqual(data["schemaVersion"], 4)
                    self.assertEqual(data["cart"]["strategy"], "profiled")
                    self.assertTrue(data["cart"]["profiles"])
                for prefix in ("1", "2"):
                    identity = f'{prefix}0000000-0000-4000-8000-{number:012d}'
                    self.assertIn(f'case .{store}: value = "{identity}"', native)

    def test_live_probes_use_the_actual_bundled_search_templates(self):
        source = (BASE / "ListRunnerUITests/StoreSelectionTests.swift").read_text()
        source = source.split("final class LiveExpansionSearchTests:", 1)[1].split("final class LiveUSSearchTests:", 1)[0]
        probes = re.findall(r'\("([^"]+)", "(https://[^"]+)", "([^"]+)"\)', source)
        self.assertEqual({store for store, _, _ in probes}, set(COUNTRIES))
        self.assertEqual(len(probes), 20)
        for store, route, _ in probes:
            with self.subTest(store=store):
                data = json.loads((BASE / f"ListRunner/Resources/{store}.json").read_text())
                template = data["search"]["template"]
                self.assertEqual(template.count("{query}"), 1)
                prefix, suffix = template.split("{query}")
                self.assertTrue(route.startswith(prefix) and route.endswith(suffix),
                                f"Probe route differs from bundled template: {route}")
                query = route[len(prefix):len(route) - len(suffix) if suffix else None]
                self.assertTrue(unquote(query))
                sample = template.replace("{query}", quote("tea & café / + #?", safe="-._~"))
                parsed = urlsplit(sample)
                self.assertEqual(parsed.scheme, "https")
                self.assertIn(parsed.hostname, data["allowedHosts"])
                self.assertFalse(parsed.fragment)
                self.assertFalse(parsed.username or parsed.password)

    def test_every_new_resource_is_in_the_xcode_resources_phase_once(self):
        project = (BASE / "ListRunner.xcodeproj/project.pbxproj").read_text()
        phase = project.split("/* Begin PBXResourcesBuildPhase section */", 1)[1].split("/* End PBXResourcesBuildPhase section */", 1)[0]
        builds = project.split("/* Begin PBXBuildFile section */", 1)[1].split("/* End PBXBuildFile section */", 1)[0]
        for store in COUNTRIES:
            with self.subTest(store=store):
                refs = re.findall(r'([A-F0-9]{24}) = \{isa = PBXFileReference;[^\n]*path = ListRunner/Resources/' + store + r'\.json;', project)
                self.assertEqual(len(refs), 1)
                entries = re.findall(r'([A-F0-9]{24}) = \{isa = PBXBuildFile; fileRef = ' + refs[0] + r';', builds)
                self.assertEqual(len(entries), 1)
                self.assertEqual(phase.count(entries[0]), 1)


if __name__ == "__main__":
    unittest.main()
