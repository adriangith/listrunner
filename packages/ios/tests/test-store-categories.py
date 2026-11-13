"""Offline contract checks for schema-7 single store categories."""
import json
from pathlib import Path
import re
import unittest

BASE = Path(__file__).resolve().parents[1]
RESOURCES = BASE / "ListRunner/Resources"
ASSIGNMENTS = {
    "amazon": "onlineMarketplace", "asda": "groceryHome", "bcf": "outdoorCamping",
    "bigW": "clothingHome", "boots": "pharmacyBeauty", "bunnings": "hardwareGarden",
    "bunningsNZ": "hardwareGarden", "chemistWarehouse": "pharmacyBeauty", "coles": "grocery",
    "costco": "groceryHome", "costcoUS": "groceryHome", "cvs": "pharmacyBeauty",
    "ikeaAU": "homeFurniture", "jbHiFi": "electronics", "kmart": "clothingHome",
    "kroger": "grocery", "morrisons": "grocery", "newWorld": "grocery", "ocado": "grocery",
    "officeworks": "officeSupplies", "paknsave": "grocery", "petbarn": "petSupplies",
    "priceline": "pharmacyBeauty", "sainsburys": "grocery", "supercheapAuto": "automotive",
    "target": "groceryHome", "targetAU": "clothingHome", "tesco": "grocery",
    "theWarehouse": "clothingHome", "waitrose": "grocery", "walgreens": "pharmacyBeauty",
    "walmart": "groceryHome", "woolworths": "grocery",
}
VOCABULARY = set(ASSIGNMENTS.values())
AUTOMATION_SCHEMA_VERSIONS = {
    "amazon": 2, "asda": 2, "bcf": 2, "bigW": 3, "boots": 2, "bunnings": 2,
    "bunningsNZ": 4, "chemistWarehouse": 4, "coles": 2, "costco": 2, "costcoUS": 2,
    "cvs": 2, "ikeaAU": 5, "jbHiFi": 4, "kmart": 3, "kroger": 2, "morrisons": 4,
    "newWorld": 2, "ocado": 4, "officeworks": 4, "paknsave": 2, "petbarn": 4,
    "priceline": 4, "sainsburys": 2, "supercheapAuto": 4, "target": 2, "targetAU": 2,
    "tesco": 4, "theWarehouse": 2, "waitrose": 4, "walgreens": 2, "walmart": 2,
    "woolworths": 2,
}


class StoreCategoryTests(unittest.TestCase):
    def test_every_registered_destination_has_one_schema7_category(self):
        source = (BASE / "ListRunner/StoreConfiguration.swift").read_text()
        registry = source.split("enum StoreID:", 1)[1].split("var id:", 1)[0]
        declarations = re.findall(r"\bcase\s+([A-Za-z][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z][A-Za-z0-9_]*)*)", registry)
        registered = {part.strip() for declaration in declarations for part in declaration.split(",")} - {"synthetic"}
        files = {path.stem for path in RESOURCES.glob("*.json") if not path.stem.startswith("ingredient")}
        self.assertEqual(registered, set(ASSIGNMENTS))
        self.assertEqual(files, registered)
        self.assertEqual(registered, set(AUTOMATION_SCHEMA_VERSIONS))
        for store, expected in ASSIGNMENTS.items():
            with self.subTest(store=store):
                data = json.loads((RESOURCES / f"{store}.json").read_text())
                self.assertEqual(data["schemaVersion"], 8 if store == "bunnings" else 7)
                self.assertEqual(data["automationSchemaVersion"], AUTOMATION_SCHEMA_VERSIONS[store])
                self.assertEqual(data["id"], store)
                self.assertEqual(data["category"], expected)
                self.assertTrue(VOCABULARY.issuperset({data["category"]}))
                self.assertNotIn("categories", data)
        self.assertNotEqual(ASSIGNMENTS["coles"], ASSIGNMENTS["costco"])
        self.assertNotEqual(ASSIGNMENTS["target"], ASSIGNMENTS["targetAU"])

    def test_native_category_enum_contains_every_assignment(self):
        source = (BASE / "ListRunner/StoreConfiguration.swift").read_text()
        declaration = source.split("enum StoreCategory:", 1)[1].split("struct StoreLoginReplay", 1)[0]
        declared = set(re.findall(r"^\s*case\s+([A-Za-z][A-Za-z0-9_]*)\s*$", declaration, re.M))
        self.assertTrue(VOCABULARY.issubset(declared))


if __name__ == "__main__":
    unittest.main()
