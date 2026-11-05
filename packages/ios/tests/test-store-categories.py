"""Offline contract checks for native retailer categories and schema-6 migration."""
import hashlib
import json
from pathlib import Path
import re
import unittest

BASE = Path(__file__).resolve().parents[1]
RESOURCES = BASE / "ListRunner/Resources"
CATEGORY_ORDER = [
    "grocery", "departmentStore", "warehouseClub", "onlineMarketplace", "hardwareGarden",
    "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "automotive", "outdoorCamping",
]

# Reviewed broad retailer classification. This is editorial metadata, not a claim
# that ListRunner automates every product type sold by each retailer.
ASSIGNMENTS = {
    "amazon": ["grocery", "onlineMarketplace", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "automotive", "outdoorCamping"],
    "asda": ["grocery", "departmentStore", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies"],
    "bcf": ["hardwareGarden", "electronics", "automotive", "outdoorCamping"],
    "bigW": ["departmentStore", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "outdoorCamping"],
    "boots": ["pharmacyBeauty"],
    "bunnings": ["hardwareGarden", "electronics", "petSupplies", "automotive", "outdoorCamping"],
    "bunningsNZ": ["hardwareGarden", "electronics", "petSupplies", "automotive", "outdoorCamping"],
    "chemistWarehouse": ["pharmacyBeauty"],
    "coles": ["grocery", "pharmacyBeauty", "petSupplies"],
    "costco": ["grocery", "warehouseClub", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "automotive", "outdoorCamping"],
    "costcoUS": ["grocery", "warehouseClub", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "automotive", "outdoorCamping"],
    "cvs": ["grocery", "pharmacyBeauty"],
    "ikeaAU": ["departmentStore", "hardwareGarden", "electronics", "officeSupplies"],
    "jbHiFi": ["electronics"],
    "kmart": ["departmentStore", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "outdoorCamping"],
    "kroger": ["grocery", "pharmacyBeauty", "petSupplies"],
    "morrisons": ["grocery", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies"],
    "newWorld": ["grocery", "pharmacyBeauty", "petSupplies"],
    "ocado": ["grocery", "pharmacyBeauty", "petSupplies"],
    "officeworks": ["electronics", "officeSupplies"],
    "paknsave": ["grocery", "pharmacyBeauty", "petSupplies"],
    "petbarn": ["petSupplies"],
    "priceline": ["pharmacyBeauty"],
    "sainsburys": ["grocery", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies"],
    "supercheapAuto": ["electronics", "automotive", "outdoorCamping"],
    "target": ["grocery", "departmentStore", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "automotive", "outdoorCamping"],
    "targetAU": ["departmentStore", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "outdoorCamping"],
    "tesco": ["grocery", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies"],
    "theWarehouse": ["departmentStore", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "outdoorCamping"],
    "waitrose": ["grocery", "pharmacyBeauty", "petSupplies"],
    "walgreens": ["grocery", "pharmacyBeauty"],
    "walmart": ["grocery", "departmentStore", "hardwareGarden", "pharmacyBeauty", "electronics", "officeSupplies", "petSupplies", "automotive", "outdoorCamping"],
    "woolworths": ["grocery", "pharmacyBeauty", "petSupplies"],
}

# SHA-256 of baseline schema-2/3/4/5 JSON objects at a39376f with only
# schemaVersion removed. This proves the upgrade preserves current main behavior.
AUTOMATION_SCHEMA_VERSIONS = {
    "amazon": 2, "asda": 2, "bcf": 2, "bigW": 3, "boots": 2, "bunnings": 2,
    "bunningsNZ": 4, "chemistWarehouse": 4, "coles": 2, "costco": 2, "costcoUS": 2,
    "cvs": 2, "jbHiFi": 4, "kmart": 3, "kroger": 2, "morrisons": 4, "newWorld": 2,
    "ocado": 4, "officeworks": 4, "paknsave": 2, "petbarn": 4, "priceline": 4,
    "sainsburys": 2, "supercheapAuto": 4, "target": 2, "targetAU": 2, "tesco": 4, "ikeaAU": 5,
    "theWarehouse": 2, "waitrose": 4, "walgreens": 2, "walmart": 2, "woolworths": 2,
}

BASELINE_CONTENT_SHA256 = {
    "amazon": "5c375199dff44785cbc30bb334b7c255027dd20dac5b666f963cf07bcc6cb5b6",
    "asda": "077d57ba3ab684ab707cfae8ae7ce424b38fd0b88a96958f443a31a40aa681d0",
    "bcf": "bbdfff12da1e66e0d905fc4091e8da002f3aa57132bc0566183b4b4b13f0dc7f",
    "bigW": "db84468c2742cb542e401713efdf1d9b6ffb9cccb4758b607d55343ce813c75f",
    "boots": "2d538daddb91ba497f60eefdd1ce85420070c1ea557f06700ca6c612be38d71c",
    "bunnings": "25db4cd7abf62fb843fb62ba4a08165b57af3d3f8fc30b44cea1aefb4e70f7cc",
    "bunningsNZ": "cf306776b3cfd1a29cfed1f37b360c0a9527fda84da1de23f71c2c9bf7eaeeec",
    "chemistWarehouse": "6634f016e0f8a10dcc70eb5633b7873eaf05ed0c2583a9fd59ff4c8a89368512",
    "coles": "e1011f6debc03d0551b78bd5a90b4736744fafa3988f99d8b2137900f45583ac",
    "costco": "ad79fb2a5847850424aabeccb18ef39b59449062bd847a9b553ad628613a2243",
    "costcoUS": "10f4d1c4454b7a233e351b50b5f0b9aba1169f6b764de6acfb5c9ef5205f2fb6",
    "cvs": "f2a4f7ee3514247dd6ea63189a5c1f4401a5b71438535bd4c8e48f225d44351d",
    "jbHiFi": "213da654d048d7d46c6024f3fcc26e3efca5156c62165c179123d35f7656e7f8",
    "kmart": "68575a6f61530e51339155be5990ca3870600a76e4f150b6531332e83da7eb0f",
    "kroger": "45ce58443a647ef66994bff536fa5d9a6d79c77d6931078659d8a0fc4902c5a5",
    "morrisons": "1d88f7c87a41b23d75990fc85f0318d388c1be8260d9074ce02aec87b3b45c89",
    "newWorld": "2eec9c76ff3cd5b034b27cf76ece1abd160922762b6dde780a96851c5bbe1f02",
    "ocado": "38526016334d5f50b288102582ddb875f25b30762afbb6cdf4c3db6550ed9a47",
    "officeworks": "48841e751ad4b6f07adb7f18cd31d984111c98bd6d5b1674dc10cc4758fb4c36",
    "paknsave": "e4a51b7c19f355063ab4323adde8875937ea70219b69d0a88ef47ca1bfdfe12e",
    "petbarn": "2329a44c7a2cef456ea05788420d307ba6842e836524e1c1038ee9deb7644f1f",
    "priceline": "84ea32c97f84b203f63042d713c7eccd0981a96797ca379196e38933b67a2473",
    "sainsburys": "f62c3f557e836966148a9962d77fd7e4f0cc794bfd7e81e33c0b1f9bfa4a41f8",
    "supercheapAuto": "83a4fcb1d79e08da62bdf8256c3278ff5f29e40f1698da794f9aef68d155e6b6",
    "target": "ecfd0e0933e1396aad8ae6cb60cc1e6c040f7e80030e721ee1cf6e6f3a101c57",
    "targetAU": "72159ede8edc2948f87bccf8a9a12b0eccb87f19cf23dd70b350618568ac1bc4",
    "tesco": "bf66b757e8f3f0374d9538fb8b97866bf27b5cd552be5e2e77092976854d548d",
    "theWarehouse": "7d11814e08eb86ab0d003f1301e907e806a871244ed597a0461511659c8b0d6b",
    "waitrose": "d0df83240844244afd42c5bc3120554f03e7b39c4040b1c7dd96d91777708728",
    "walgreens": "446598de8521926effdfbbc158c0860f561510c9d8e18a97f270855b7bee1f35",
    "walmart": "45573e4c0c85b15202e19c622dafa54dbc730ac355c7fdd6c517cc5450ae33ce",
    "woolworths": "b795ee340fa043ecf1b0ab57dbe4b80443b10c1f6e242fb96a2dc69f34e4b42c",
    "ikeaAU": "dd7b0a3ca5b7dc2decf49332769a9223b6d00f1ed32bd9b59f3a16b11bf0f7ef",
}


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(encoded).hexdigest()


class StoreCategoryTests(unittest.TestCase):
    def test_every_registered_destination_has_exact_schema6_classification(self):
        source = (BASE / "ListRunner/StoreConfiguration.swift").read_text()
        registry = source.split("enum StoreID:", 1)[1].split("var id: String", 1)[0]
        declarations = re.findall(r"\bcase\s+([A-Za-z][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z][A-Za-z0-9_]*)*)", registry)
        registered = {part.strip() for declaration in declarations for part in declaration.split(",")} - {"synthetic"}
        files = {path.stem for path in RESOURCES.glob("*.json") if not path.stem.startswith("ingredient")}
        self.assertEqual(registered, set(ASSIGNMENTS))
        self.assertEqual(files, registered)
        self.assertEqual(set(BASELINE_CONTENT_SHA256), registered)
        self.assertEqual(set(AUTOMATION_SCHEMA_VERSIONS), registered)
        for store, expected in ASSIGNMENTS.items():
            with self.subTest(store=store):
                data = json.loads((RESOURCES / f"{store}.json").read_text())
                self.assertEqual(data["schemaVersion"], 6)
                self.assertEqual(data["automationSchemaVersion"], AUTOMATION_SCHEMA_VERSIONS[store])
                self.assertEqual(data["id"], store)
                self.assertEqual(data["categories"], expected)
                self.assertTrue(data["categories"])
                self.assertEqual(len(data["categories"]), len(set(data["categories"])))
                self.assertTrue(set(data["categories"]).issubset(CATEGORY_ORDER))
                self.assertEqual(data["categories"], [c for c in CATEGORY_ORDER if c in data["categories"]])
                unchanged = {key: value for key, value in data.items()
                             if key not in {"schemaVersion", "categories", "automationSchemaVersion"}}
                self.assertEqual(canonical_hash(unchanged), BASELINE_CONTENT_SHA256[store],
                                 "migration must preserve all non-version, non-category configuration")

    def test_native_category_enum_matches_stable_wire_vocabulary(self):
        source = (BASE / "ListRunner/StoreConfiguration.swift").read_text()
        declaration = source.split("enum StoreCategory:", 1)[1].split("struct StoreDefinition", 1)[0]
        declared = re.findall(r"^\s*case\s+([A-Za-z][A-Za-z0-9_]*)\s*$", declaration, re.M)
        self.assertEqual(declared, CATEGORY_ORDER)


if __name__ == "__main__":
    unittest.main()
