#!/usr/bin/env python3
"""Store onboarding tools. No capability promotion; live search requires explicit opt-in."""
import argparse
import base64
import html
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit, quote

# Also importable by the standalone regression suite without package installation.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from store_registration import registration_files, make_patch, resource_contract

BASE = Path(__file__).resolve().parents[1]
RESOURCES = BASE / 'ListRunner/Resources'


def load_config(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate JSON key: {key}')
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


def validate(config):
    errors = []
    if not isinstance(config, dict):
        return ['Configuration must be an object']
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', str(config.get('id', ''))):
        errors.append('Invalid store id')
    required = {'schemaVersion', 'id', 'displayName', 'serviceArea', 'homepage', 'allowedHosts',
                'search', 'addedColor', 'capabilities', 'cart'}
    if not required.issubset(config) or set(config) - required - {'brandColors'}:
        errors.append('Missing or unknown store configuration fields')
    if not isinstance(config.get('displayName'), str) or not config['displayName'].strip():
        errors.append('Display name must be nonempty text')
    color = config.get('addedColor')
    if (not isinstance(color, dict) or set(color) != {'red', 'green', 'blue'} or
            any(type(value) is not int or not 0 <= value <= 255 for value in color.values())):
        errors.append('Brand color requires integer red/green/blue channels between 0 and 255')
    area = config.get('serviceArea')
    countries = area.get('countryCodes') if isinstance(area, dict) else None
    if (not isinstance(countries, list) or not countries or
            any(not isinstance(c, str) or not re.fullmatch('[A-Z]{2}', c) for c in countries)):
        errors.append('Service area needs uppercase two-letter country codes; native validation checks ISO membership')
    hosts = config.get('allowedHosts')
    if (not isinstance(hosts, list) or not hosts or
            any(not isinstance(h, str) or not re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)+', h) for h in hosts)):
        errors.append('Use nonempty exact lowercase DNS hosts, not wildcards')
        hosts = []
    if len(hosts) != len(set(hosts)):
        errors.append('Duplicate hosts')
    search = config.get('search', {})
    if isinstance(search, dict):
        selector = search.get('resultsSelector')
        offset = search.get('resultsTopOffset')
        if selector is not None and (not isinstance(selector, str) or
                not selector.strip() or len(selector.encode('utf-8')) > 1024):
            errors.append('resultsSelector must be nonempty CSS, at most 1024 UTF-8 bytes')
        if offset is not None and (selector is None or type(offset) not in (int, float) or
                not math.isfinite(offset) or not 0 <= offset <= 500):
            errors.append('resultsTopOffset requires a selector and a finite number from 0 to 500 CSS pixels')
    template = search.get('template', '') if isinstance(search, dict) else ''
    if not isinstance(template, str):
        template = ''
    if template.count('{query}') != 1:
        errors.append('Search template needs exactly one {query}')
    for name, value in [('homepage', config.get('homepage')), ('search', template)]:
        try:
            if not isinstance(value, str):
                raise ValueError('URL must be text')
            url = urlsplit(value or '')
            if (url.scheme != 'https' or url.hostname not in hosts or url.username or
                    url.password or url.port not in (None, 443) or url.fragment):
                errors.append(f'{name} must use an exact allowed HTTPS origin without credentials/fragment')
        except ValueError:
            errors.append(f'Invalid {name} URL')
    caps = config.get('capabilities')
    if not isinstance(caps, dict) or any(type(caps.get(k)) is not bool for k in ('search', 'cartDetection', 'cartUndo')):
        errors.append('All three capability flags must be booleans')
    elif caps['cartUndo'] and not caps['cartDetection']:
        errors.append('Undo requires detection')
    elif caps['cartDetection'] and config.get('cart') is None:
        errors.append('Detection requires a reviewed cart strategy')
    return errors


def scaffold(args):
    config = {
        'schemaVersion': 2, 'id': args.id, 'displayName': args.name,
        'serviceArea': {'countryCodes': [args.country]},
        'homepage': args.homepage, 'allowedHosts': args.host,
        'search': {'strategy': 'urlTemplate', 'template': args.search},
        'addedColor': {'red': 64, 'green': 64, 'blue': 64},
        'capabilities': {'search': False, 'cartDetection': False, 'cartUndo': False},
        'cart': None,
    }
    errors = validate(config)
    if not re.fullmatch('[A-Z]{2}', args.country):
        errors.append('Country must be a two-letter uppercase code')
    if not args.name.strip():
        errors.append('Display name is required')
    native = (BASE / 'ListRunner/StoreConfiguration.swift').read_text()
    if (RESOURCES / f'{args.id}.json').exists() or re.search(r'\b' + re.escape(args.id) + r'\b', native):
        errors.append('Store id already exists')
    if errors:
        raise ValueError('; '.join(errors))
    # Exclusive directory creation: never overwrite an existing draft or app file.
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / f'{args.id}.json').write_text(json.dumps(config, indent=2) + '\n')
    (args.output / 'STATUS.md').write_text(f'''# {args.name} onboarding

Draft only; not registered, shipped or verified. All capabilities disabled.

- [ ] Confirm requested scope and live-test authorization
- [ ] Early native read-only feasibility: exact host, query reflection, distinct results
- [ ] Record consent/location/verification blockers; stop rather than bypass
- [ ] Reserve permanent list and website-data UUIDs against the latest shared branch
- [ ] Review exact native hosts, homepage, data ownership and regional grouping
- [ ] Add StoreID registration; keep native capability ceilings off
- [ ] Review branding, disabled-default visibility and discovery availability
- [ ] Copy reviewed JSON into Resources and register once in Xcode resources
- [ ] Add focused fixtures and native checks; use existing shared strategies
- [ ] Run offline check command and separately authorized native live checks
- [ ] Record revision, device/OS, evidence paths and outcome for each capability
- [ ] Enable only individually proved capabilities in native policy and JSON

Search: unverified. Detection: unverified. Undo: unverified.
Strategy fit: not assessed. Blockers: not assessed.
Evidence revision/device/paths: not recorded.

See docs/adding-a-store.md. Do not infer live proof from offline checks.
''')
    print(f'Draft created: {args.output}. No app registration or permissions changed.')


def check(args):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', args.id):
        raise ValueError('Invalid store id')
    config = load_config(RESOURCES / f'{args.id}.json')
    errors = validate(config)
    if config.get('id') != args.id:
        errors.append('Filename and store id differ')
    native = (BASE / 'ListRunner/StoreConfiguration.swift').read_text()
    enum = native.split('enum StoreID:', 1)[1].split('var id:', 1)[0]
    registered = {name.strip().strip('`') for line in enum.splitlines() if line.lstrip().startswith('case ')
                  for name in line.strip()[len('case '):].split(',')}
    if args.id not in registered:
        errors.append('Store ID is not registered in the native StoreID enum')
    errors.extend(resource_contract((BASE / 'ListRunner.xcodeproj/project.pbxproj').read_text(), args.id))
    if errors:
        raise ValueError('; '.join(errors))
    preferred = Path('/tmp/opencode')
    directory = Path(tempfile.mkdtemp(prefix='store-onboarding-', dir=preferred if preferred.is_dir() else None))
    results = []
    if shutil.which('xcrun'):
        # The established macOS suite already includes every portable check.
        commands = [('native-offline', ['bash', str(BASE / 'tests/run-cloud-checks.sh')])]
    else:
        commands = [
            ('registration', [sys.executable, '-B', str(BASE / 'tests/test-store-expansion.py')]),
            ('resources', [sys.executable, '-B', str(BASE / 'tests/test-bundled-resources.py')]),
            ('tooling', [sys.executable, '-B', str(BASE / 'tests/test-store-onboarding.py')]),
            ('cloud-contracts', [sys.executable, '-B', str(BASE / 'tests/test-cloud-ci.py')]),
            ('strategies', ['node', '--test', '--test-reporter=dot', *[str(BASE / 'tests' / f) for f in
                ('bigw-cart-detection.test.mjs', 'coles-add-detection.test.mjs', 'profiled-expansion-cart.test.mjs')]]),
            ('inspection', ['node', '--test', '--test-reporter=dot', str(BASE / 'tests/store-inspection.test.mjs')]),
        ]
    for name, command in commands:
        log = directory / f'{name}.log'
        with log.open('w') as output:
            try:
                process = subprocess.run(command, cwd=BASE, stdout=output, stderr=subprocess.STDOUT, timeout=300)
                status = 'pass' if process.returncode == 0 else 'fail'
            except (OSError, subprocess.TimeoutExpired) as error:
                output.write(str(error))
                status = 'fail'
        results.append({'check': name, 'status': status, 'log': str(log)})
        print(f'{status.upper()}: {name} ({log})')
    if not shutil.which('xcrun'):
        results.append({'check': 'native-offline', 'status': 'blocked', 'reason': 'Requires macOS/Xcode'})
        print('BLOCKED: native offline checks require macOS/Xcode')
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=BASE, capture_output=True, text=True, check=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=BASE, capture_output=True, text=True, check=True).stdout)
    report = {'store': args.id, 'revision': revision, 'workingTreeDirty': dirty,
              'scope': 'offline-only', 'checks': results,
              'liveVerification': 'not run; offline success does not certify capabilities'}
    (directory / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {directory / "report.json"}')
    return 1 if any(r['status'] == 'fail' for r in results) else (2 if any(r['status'] == 'blocked' for r in results) else 0)


def register(args):
    config = load_config(args.config)
    errors = validate(config)
    if errors:
        raise ValueError('; '.join(errors))
    files = registration_files(BASE.parents[1], config, args.serial, args.data_domain)
    with args.output.open('x') as output:
        output.write(make_patch(files))
    print(f'Review patch: {args.output}. No checkout files changed; all capabilities stay off.')
    print('After reviewing trust, permanent identities and latest shared branches, use git apply --check then git apply.')


def probe_plan(args):
    config = load_config(args.config)
    errors = validate(config)
    if errors:
        raise ValueError('; '.join(errors))
    if len(args.query) != 2 or any(not q.strip() or len(q) > 80 for q in args.query) or args.query[0].casefold() == args.query[1].casefold():
        raise ValueError('Provide exactly two distinct, unrelated public product queries (up to 80 characters each)')
    script = (BASE / 'tools/inspect-store.js').read_text()
    queries = []
    for index, query in enumerate(args.query):
        options = dict(query=query, productSelector=args.product_selector,
                       querySelector=args.query_selector, addSelector=args.add_selector,
                       containerSelector=args.container_selector)
        entry = dict(query=query, url=config['search']['template'].replace('{query}', quote(query, safe='-._~')),
                     script='(' + script + ')(' + json.dumps(options) + ')')
        if args.fixture:
            # Synthetic HTML only. Native fixture mode blocks all network requests.
            entry['fixtureHTML'] = '<h1>' + html.escape(query) + '</h1>' + ''.join(
                f'<article><a href="/product/{index}-{number}">{html.escape(query)} {number}</a><button>Add</button></article>'
                for number in range(3))
        queries.append(entry)
    plan = dict(id=config['id'], hosts=config['allowedHosts'], queries=queries,
                fixtureOnly=args.fixture, configSHA256=hashlib.sha256(args.config.read_bytes()).hexdigest(),
                scope='read-only search inspection; no capability promotion')
    with args.output.open('x') as output:
        output.write(json.dumps(plan, indent=2) + '\n')
    print(f'Probe plan: {args.output}. No website visited. Review the selectors and queries before running.')


def probe(args):
    if not shutil.which('xcrun'):
        raise ValueError('Native search probes require macOS/Xcode')
    data = args.plan.read_bytes()
    plan = json.loads(data)
    if bool(plan.get('fixtureOnly')) != args.fixture:
        raise ValueError('Fixture/live mode mismatch; no implicit fallback to real websites')
    if not args.fixture and not args.allow_live_search:
        raise ValueError('Live read-only GET search requires --allow-live-search; never permits cart actions or consent changes')
    if len(data) > 40000:
        raise ValueError('Probe plan too large for the test environment')
    directory = Path(tempfile.mkdtemp(prefix='store-onboarding-native-'))
    import os
    environment = os.environ.copy()
    for key, value in dict(LISTRUNNER_ONBOARDING_PLAN=base64.b64encode(data).decode(),
                           LISTRUNNER_ONBOARDING_MODE='fixture' if args.fixture else 'live-read-only').items():
        environment['TEST_RUNNER_' + key] = value
    # Cache per worktree outside source control, not per attempt. The initial build
    # is expensive; subsequent stores should not compile the entire app again.
    cache = getattr(args, 'derived_data', None) or (Path(tempfile.gettempdir()) /
        ('listrunner-onboarding-build-' + hashlib.sha256(str(BASE).encode()).hexdigest()[:12]))
    command = ['xcodebuild', 'test', '-project', str(BASE / 'ListRunner.xcodeproj'), '-scheme', 'ListRunner',
               '-destination', args.destination, '-derivedDataPath', str(cache),
               '-resultBundlePath', str(directory / 'inspection.xcresult'),
               '-only-testing:ListRunnerUITests/StoreOnboardingSearchTests/testSearchPlan', 'CODE_SIGNING_ALLOWED=NO']
    log = directory / 'xcodebuild.log'
    print(f'Running only native search inspection; log: {log}', flush=True)
    started = time.monotonic()
    with log.open('w') as output:
        result = subprocess.run(command, cwd=BASE, env=environment, stdout=output, stderr=subprocess.STDOUT, timeout=600)
    summary = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path',
                              str(directory / 'inspection.xcresult'), '--format', 'json'],
                             capture_output=True, text=True, timeout=30)
    try:
        details = json.loads(summary.stdout) if summary.returncode == 0 else {}
    except json.JSONDecodeError:
        details = {}
    exported = directory / 'attachments'
    export = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path',
                             str(directory / 'inspection.xcresult'), '--output-path', str(exported)],
                            capture_output=True, text=True, timeout=30)
    mode = 'offline-fixture' if args.fixture else 'live-read-only'
    inspection = inspection_artifact(exported, plan['id'], mode) if export.returncode == 0 else None
    passed = result.returncode == 0 and native_summary_passed(details) and inspection is not None
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=BASE, capture_output=True, text=True, check=True).stdout.strip()
    (directory / 'report.json').write_text(json.dumps(dict(
        store=plan['id'], mode=mode,
        status='pass' if passed else 'fail', elapsedSeconds=round(time.monotonic() - started, 3),
        revision=revision, configSHA256=plan.get('configSHA256'),
        planSHA256=hashlib.sha256(data).hexdigest(), testSummary=details, inspection=inspection,
        cartVerification='not-performed', capabilitiesChanged=False), indent=2) + '\n')
    print(f'{"PASS" if passed else "FAIL"}: {"offline fixture" if args.fixture else "live read-only search"}; report: {directory / "report.json"}')
    print(f'Native evidence: {directory / "inspection.xcresult"}. No cart proof or capability changes.')
    return 0 if passed else 1


def native_summary_passed(details):
    # A green xcodebuild command with skipped/zero tests is not search proof.
    return (details.get('result') == 'Passed' and details.get('totalTestCount') == 1
            and details.get('passedTests') == 1 and details.get('failedTests') == 0
            and details.get('skippedTests') == 0)


def inspection_artifact(directory, store, mode):
    candidates = []
    for path in directory.glob('*.json'):
        try:
            value = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if (isinstance(value, dict) and value.get('store') == store and value.get('mode') == mode
                and value.get('capabilitiesChanged') is False and value.get('cartVerification') == 'not-performed'
                and isinstance(value.get('observations'), list) and len(value['observations']) == 2):
            candidates.append(value)
    return candidates[0] if len(candidates) == 1 else None


def strategies(args):
    examples = {}
    for path in sorted(RESOURCES.glob('*.json')):
        config = json.loads(path.read_text())
        cart = config.get('cart')
        if not cart:
            continue
        for profile in cart.get('profiles') or [cart]:
            key = (cart['strategy'], cart['identityStrategy'], profile.get('confirmation', 'quantityIncrease'))
            entry = examples.setdefault(key, {'configured': [], 'enabledDetection': []})
            if config['id'] not in entry['configured']:
                entry['configured'].append(config['id'])
            if config['capabilities']['cartDetection'] and config['id'] not in entry['enabledDetection']:
                entry['enabledDetection'].append(config['id'])
    print(json.dumps([dict(strategy=key[0], identity=key[1], confirmation=key[2], **value)
                      for key, value in examples.items()], indent=2))
    print('Configured examples are not certification. Review native constraints and live evidence before reuse.', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    draft = commands.add_parser('scaffold', help='Create an unregistered, disabled draft; never edits runtime policy')
    for flag in ('id', 'name', 'country', 'homepage', 'search'):
        draft.add_argument('--' + flag, required=True)
    draft.add_argument('--host', action='append', required=True, help='Repeat for each reviewed exact host')
    draft.add_argument('--output', type=Path, required=True, help='New directory, preferably outside checkout')
    verify = commands.add_parser('check', help='Compact offline test report; exit 2 means native checks blocked')
    verify.add_argument('id')
    registration = commands.add_parser('register', help='Generate disabled native + Xcode + JSON registration patch')
    registration.add_argument('--config', type=Path, required=True)
    registration.add_argument('--serial', type=int, help='Optional reviewed unused suffix; default generates permanent UUIDs once')
    registration.add_argument('--data-domain', required=True, help='Reviewed website-data ownership domain')
    registration.add_argument('--output', type=Path, required=True, help='New patch file; never overwritten')
    plan = commands.add_parser('probe-plan', help='Generate two-query native inspection plan; no network access')
    plan.add_argument('--config', type=Path, required=True)
    plan.add_argument('--query', action='append', required=True)
    plan.add_argument('--product-selector', required=True, help='Reviewed selector of product links, not general navigation')
    plan.add_argument('--query-selector', default='h1,h2,input[type="search"]')
    plan.add_argument('--add-selector', default='button[data-testid="add-to-cart"]')
    plan.add_argument('--container-selector', default='article')
    plan.add_argument('--fixture', action='store_true', help='Generate synthetic network-blocked HTML instead of live routes')
    plan.add_argument('--output', type=Path, required=True)
    native = commands.add_parser('probe', help='Run only the generic iOS WebKit inspection test on a selected simulator')
    native.add_argument('--plan', type=Path, required=True)
    native.add_argument('--destination', required=True, help='Explicit xcodebuild simulator destination; do not interrupt another task')
    native.add_argument('--fixture', action='store_true')
    native.add_argument('--allow-live-search', action='store_true')
    native.add_argument('--derived-data', type=Path, help='Optional external build cache; default is isolated per worktree')
    commands.add_parser('strategies', help='Small strategy/example inventory derived from current bundled data')
    args = parser.parse_args()
    try:
        return {'scaffold': scaffold, 'check': check, 'register': register,
                'probe-plan': probe_plan, 'probe': probe, 'strategies': strategies}[args.command](args)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
