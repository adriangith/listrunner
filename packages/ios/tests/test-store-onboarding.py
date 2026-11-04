"""Offline tooling regressions; all generated artifacts stay in temporary dirs."""
import argparse
import contextlib
import io
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
import uuid
import re
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('onboarding', Path(__file__).resolve().parents[1] / 'tools/store-onboarding.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class OnboardingTests(unittest.TestCase):
    def args(self, output):
        return argparse.Namespace(id='exampleAU', name='Example', country='AU',
            homepage='https://shop.example/au/', host=['shop.example'],
            search='https://shop.example/search?q={query}', output=output)

    def test_scaffold_disabled_and_non_destructive(self):
        with tempfile.TemporaryDirectory() as root:
            args = self.args(Path(root) / 'draft')
            tool.scaffold(args)
            config = json.loads((args.output / 'exampleAU.json').read_text())
            self.assertEqual(tool.validate(config), [])
            self.assertEqual(config['capabilities'], dict(search=False, cartDetection=False, cartUndo=False))
            self.assertIsNone(config['cart'])
            self.assertTrue((args.output / 'STATUS.md').exists())
            with self.assertRaises(FileExistsError):
                tool.scaffold(args)

    def test_rejects_existing_identity(self):
        with tempfile.TemporaryDirectory() as root:
            args = self.args(Path(root) / 'draft')
            args.id = 'coles'
            with self.assertRaisesRegex(ValueError, 'already exists'):
                tool.scaffold(args)
            self.assertFalse(args.output.exists())

    def test_rejects_unsafe_input_before_writing(self):
        changes = [('id', '../escape'), ('host', ['*.example']),
                   ('homepage', 'http://shop.example'), ('homepage', 'https://user@shop.example'),
                   ('homepage', 'https://shop.example:444/'), ('country', 'Australia'),
                   ('search', 'https://evil.example/?q={query}'),
                   ('search', 'https://shop.example/?q=milk'), ('name', '')]
        with tempfile.TemporaryDirectory() as root:
            for key, value in changes:
                with self.subTest(key=key, value=value):
                    args = self.args(Path(root) / 'draft')
                    setattr(args, key, value)
                    with self.assertRaises(ValueError):
                        tool.scaffold(args)
                    self.assertFalse(args.output.exists())

    def test_all_existing_store_resources_pass_preflight(self):
        project = (tool.BASE / 'ListRunner.xcodeproj/project.pbxproj').read_text()
        for resource in tool.RESOURCES.glob('*.json'):
            config = json.loads(resource.read_text())
            if 'id' in config and 'capabilities' in config:
                with self.subTest(store=resource.name):
                    self.assertEqual(tool.validate(config), [])
                    self.assertEqual(tool.resource_contract(project, config['id']), [])

    def test_invalid_capability_types(self):
        config = json.loads((tool.RESOURCES / 'coles.json').read_text())
        config['capabilities']['search'] = 'true'
        self.assertTrue(tool.validate(config))
        config['capabilities'] = dict(search=True, cartDetection=False, cartUndo=True)
        self.assertTrue(tool.validate(config))

    def test_duplicate_keys_are_rejected_before_generation(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'bad.json'
            path.write_text('{"allowedHosts": ["safe.example"], "allowedHosts": ["other.example"]}')
            with self.assertRaisesRegex(ValueError, 'Duplicate JSON key'):
                tool.load_config(path)

    def test_check_rejects_path_traversal(self):
        with self.assertRaisesRegex(ValueError, 'Invalid store id'):
            tool.check(argparse.Namespace(id='../coles'))

    def test_report_preserves_blocked_and_failed_results(self):
        for failure, expected in [(False, 2), (True, 1)]:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as root:
                def run(command, **kwargs):
                    if command[:2] == ['git', 'rev-parse']:
                        return argparse.Namespace(stdout='abc123\n', returncode=0)
                    if command[:2] == ['git', 'status']:
                        return argparse.Namespace(stdout='?? draft\n', returncode=0)
                    return argparse.Namespace(returncode=1 if failure else 0)
                with patch.object(tool.shutil, 'which', return_value=None), \
                     patch.object(tool.tempfile, 'mkdtemp', return_value=root), \
                     patch.object(tool.subprocess, 'run', side_effect=run):
                    self.assertEqual(tool.check(argparse.Namespace(id='coles')), expected)
                report = json.loads((Path(root) / 'report.json').read_text())
                self.assertEqual(report['scope'], 'offline-only')
                self.assertEqual(report['revision'], 'abc123')
                self.assertTrue(report['workingTreeDirty'])
                self.assertEqual(report['checks'][-1]['status'], 'blocked')
                self.assertIn('not run', report['liveVerification'])

    def test_registration_end_to_end_without_shipping_store(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            draft = root / 'draft'
            tool.scaffold(self.args(draft))
            config = json.loads((draft / 'exampleAU.json').read_text())
            files = tool.registration_files(tool.BASE.parents[1], config, None, 'shop.example')
            for path, (before, _) in files.items():
                if before:
                    target = root / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(before)
            patch_file = root / 'registration.patch'
            patch_file.write_text(tool.make_patch(files))
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            subprocess.run(['git', 'apply', '--check', str(patch_file)], cwd=root, check=True)
            subprocess.run(['git', 'apply', str(patch_file)], cwd=root, check=True)
            native = (root / 'packages/ios/ListRunner/StoreConfiguration.swift').read_text()
            self.assertIn('case `exampleAU`', native)
            identities = re.findall(r'case \.`exampleAU`: value = "([A-F0-9-]+)"', native)
            self.assertEqual(len(set(identities)), 2)
            self.assertTrue(all(uuid.UUID(value).version == 4 for value in identities))
            # Every added native line belongs only to the new store. Removing them
            # must reproduce the original bytes, including all capability ceilings.
            self.assertEqual(''.join(line for line in native.splitlines(True) if 'exampleAU' not in line),
                             files['packages/ios/ListRunner/StoreConfiguration.swift'][0])
            resource = root / 'packages/ios/ListRunner/Resources/exampleAU.json'
            self.assertEqual(json.loads(resource.read_text()), config)
            project = (root / 'packages/ios/ListRunner.xcodeproj/project.pbxproj').read_text()
            self.assertEqual(project.count('path = ListRunner/Resources/exampleAU.json;'), 1)
            self.assertEqual(tool.resource_contract(project, 'exampleAU'), [])
            with self.assertRaisesRegex(ValueError, 'already registered'):
                tool.registration_files(root, config, 1000, 'shop.example')
            # On macOS, actually compile the expanded native enum, decode the new
            # resource and verify its trusted metadata and disabled capabilities.
            if shutil.which('xcrun'):
                sources = ['StoreConfiguration.swift', 'IngredientQuantity.swift', 'IngredientParseResult.swift',
                           'IngredientDictionary.swift', 'IngredientParser.swift', 'RegionalIngredientSearchResolver.swift']
                proof = root / 'Proof.swift'
                proof.write_text('''import Foundation
@main struct Proof {
    @MainActor static func main() throws {
        let id = StoreID(rawValue: "exampleAU")!
        precondition(id.home.absoluteString == "https://shop.example/au/")
        precondition(id.hosts == ["shop.example"] && id.dataDomain == "shop.example")
        precondition(!id.permitsSearch && !id.permitsCartDetection && !id.permitsCartUndo)
        let suite = "OnboardingProof.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(!StoreVisibilityPreferences(defaults: defaults).visibleIDs.contains(id))
        precondition(Set(StoreID.allCases.map(\\.listID)).count == StoreID.allCases.count)
        precondition(Set(StoreID.allCases.map(\\.websiteDataID)).count == StoreID.allCases.count)
        let store = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(store.id == id && store.isConfigurationValid && !store.isAvailableForShopping)
        print("PASS: generated native registration, trust, IDs, decoding and hidden capability gates")
    }
}
''')
                paths = [str(root / 'packages/ios/ListRunner' / name) if name == 'StoreConfiguration.swift'
                         else str(tool.BASE / 'ListRunner' / name) for name in sources]
                binary = root / 'proof'
                subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *paths, str(proof), '-o', str(binary)], check=True)
                subprocess.run([str(binary), str(resource)], check=True)
                subprocess.run(['plutil', '-lint', str(root / 'packages/ios/ListRunner.xcodeproj/project.pbxproj')], check=True)

    def test_registration_refuses_collisions_and_permissions(self):
        with tempfile.TemporaryDirectory() as root:
            draft = Path(root) / 'draft'
            tool.scaffold(self.args(draft))
            config = json.loads((draft / 'exampleAU.json').read_text())
            with self.assertRaisesRegex(ValueError, 'already reserved'):
                tool.registration_files(tool.BASE.parents[1], config, 1, 'shop.example')
            with self.assertRaisesRegex(ValueError, 'Every navigation host'):
                tool.registration_files(tool.BASE.parents[1], config, 999, 'evil.example')
            config['capabilities']['search'] = True
            with self.assertRaisesRegex(ValueError, 'disabled'):
                tool.registration_files(tool.BASE.parents[1], config, 999, 'shop.example')

    def test_default_registration_allocates_permanent_independent_ids_in_source_only(self):
        with tempfile.TemporaryDirectory() as root:
            draft = Path(root) / 'draft'
            tool.scaffold(self.args(draft))
            config = json.loads((draft / 'exampleAU.json').read_text())
            files = tool.registration_files(tool.BASE.parents[1], config, None, 'shop.example')
            native = files['packages/ios/ListRunner/StoreConfiguration.swift'][1]
            ids = re.findall(r'case \.`exampleAU`: value = "([A-F0-9-]+)"', native)
            self.assertEqual(len(ids), 2)
            self.assertEqual(len(set(ids)), 2)
            for value in ids:
                self.assertEqual(uuid.UUID(value).version, 4)
                self.assertNotIn(value, files['packages/ios/ListRunner/StoreConfiguration.swift'][0])
            self.assertNotIn('UUID()', native) # no runtime reallocation
            explicit = tool.registration_files(tool.BASE.parents[1], config, 999, 'shop.example')
            self.assertIn('10000000-0000-4000-8000-000000000999', explicit['packages/ios/ListRunner/StoreConfiguration.swift'][1])
            self.assertIn('20000000-0000-4000-8000-000000000999', explicit['packages/ios/ListRunner/StoreConfiguration.swift'][1])

    def test_registration_refuses_changed_layout_and_invalid_branding(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tool.scaffold(self.args(root / 'draft'))
            config = json.loads((root / 'draft/exampleAU.json').read_text())
            config['addedColor']['red'] = 999
            with self.assertRaisesRegex(ValueError, 'Brand color'):
                tool.registration_files(tool.BASE.parents[1], config, 999, 'shop.example')
            config['addedColor']['red'] = 64
            for path in ['packages/ios/ListRunner/StoreConfiguration.swift',
                         'packages/ios/ListRunner.xcodeproj/project.pbxproj']:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text((tool.BASE.parents[1] / path).read_text())
            native = root / 'packages/ios/ListRunner/StoreConfiguration.swift'
            native.write_text(native.read_text().replace('    var home: URL {', '    var home: URL{'))
            with self.assertRaisesRegex(ValueError, 'layout changed'):
                tool.registration_files(root, config, 999, 'shop.example')

    def test_project_contract_catches_missing_duplicate_and_unbundled_resources(self):
        project = (tool.BASE / 'ListRunner.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(tool.resource_contract(project, 'coles'), [])
        self.assertTrue(tool.resource_contract(project, 'missing'))
        reference = next(line for line in project.splitlines() if 'isa = PBXFileReference;' in line and 'path = Resources/coles.json;' in line)
        self.assertTrue(tool.resource_contract(project + '\n' + reference, 'coles'))
        self.assertTrue(tool.resource_contract(project.replace('fileRef = B10000000000000000000016',
                                                              'fileRef = B10000000000000000000017'), 'coles'))

    def test_plan_generation_quotes_queries_and_never_enables_capabilities(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tool.scaffold(self.args(root / 'draft'))
            args = argparse.Namespace(config=root / 'draft/exampleAU.json', query=['tea & café', 'bread'],
                product_selector='a[href*="/product/"]', query_selector='h1', add_selector='button',
                container_selector='article', fixture=True, output=root / 'plan.json')
            tool.probe_plan(args)
            plan = json.loads(args.output.read_text())
            self.assertTrue(plan['fixtureOnly'])
            self.assertEqual(len(plan['configSHA256']), 64)
            self.assertIn('tea%20%26%20caf%C3%A9', plan['queries'][0]['url'])
            self.assertIn('tea &amp; café', plan['queries'][0]['fixtureHTML'])
            self.assertIn('options =>', plan['queries'][0]['script'])
            with self.assertRaises(FileExistsError):
                tool.probe_plan(args)
            self.assertFalse(json.loads(args.config.read_text())['capabilities']['search'])

    def test_probe_requires_explicit_mode_and_authorization(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'plan.json'
            path.write_text('{"fixtureOnly": false}')
            args = argparse.Namespace(plan=path, fixture=False, allow_live_search=False, destination='unused')
            with patch.object(tool.shutil, 'which', return_value='xcrun'):
                with self.assertRaisesRegex(ValueError, 'requires --allow-live-search'):
                    tool.probe(args)
                args.fixture = True
                with self.assertRaisesRegex(ValueError, 'mode mismatch'):
                    tool.probe(args)

    def test_strategy_inventory_is_derived_and_marks_configuration_not_proof(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            tool.strategies(argparse.Namespace())
        inventory = json.loads(output.getvalue())
        self.assertTrue(any('coles' in row['enabledDetection'] for row in inventory))
        self.assertTrue(any(row['confirmation'] == 'productAcknowledgement' for row in inventory))

    def test_native_summary_rejects_skipped_zero_failed_and_missing_test_runs(self):
        good = dict(result='Passed', totalTestCount=1, passedTests=1, failedTests=0, skippedTests=0)
        self.assertTrue(tool.native_summary_passed(good))
        for key, value in [('result', 'Failed'), ('totalTestCount', 0), ('passedTests', 0),
                           ('failedTests', 1), ('skippedTests', 1)]:
            with self.subTest(key=key):
                self.assertFalse(tool.native_summary_passed(dict(good, **{key: value})))
        self.assertFalse(tool.native_summary_passed({}))

    def test_inspection_artifact_requires_one_matching_native_attachment(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            payload = dict(store='exampleAU', mode='offline-fixture', capabilitiesChanged=False,
                           cartVerification='not-performed', observations=[{}, {}])
            self.assertIsNone(tool.inspection_artifact(root, 'exampleAU', 'offline-fixture'))
            (root / 'result.json').write_text(json.dumps(payload))
            self.assertEqual(tool.inspection_artifact(root, 'exampleAU', 'offline-fixture'), payload)
            self.assertIsNone(tool.inspection_artifact(root, 'exampleAU', 'live-read-only'))
            self.assertIsNone(tool.inspection_artifact(root, 'otherAU', 'offline-fixture'))
            (root / 'duplicate.json').write_text(json.dumps(payload))
            self.assertIsNone(tool.inspection_artifact(root, 'exampleAU', 'offline-fixture'))


if __name__ == '__main__':
    unittest.main(buffer=True)
