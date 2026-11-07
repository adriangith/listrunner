"""Generate a reviewable registration diff without rewriting shared runtime policy."""
import difflib
import hashlib
import json
import re
import uuid

NATIVE = 'packages/ios/ListRunner/StoreConfiguration.swift'
PROJECT = 'packages/ios/ListRunner.xcodeproj/project.pbxproj'


def once(text, marker, insertion):
    if text.count(marker) != 1:
        raise ValueError(f'Registration layout changed; expected one marker: {marker!r}')
    return text.replace(marker, insertion + marker, 1)


def swift_string(value):
    # Swift interpolation must not be interpreted in developer-provided metadata.
    if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('Native metadata must be text without control characters')
    return json.dumps(value, ensure_ascii=False)


def registration_files(root, config, serial, domain):
    """Return proposed files; caller writes only a patch, never the checkout."""
    store = config['id']
    # Backtick-escaped Swift case identifiers also support reserved words safely.
    if not re.fullmatch('[a-z][A-Za-z0-9]*', store):
        raise ValueError('Native store ids must start with a lowercase ASCII letter')
    if not re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)+', domain):
        raise ValueError('Review an exact website-data domain')
    if not all(host == domain or host.endswith('.' + domain) for host in config['allowedHosts']):
        raise ValueError('Every navigation host must belong to the reviewed website-data domain')
    if serial is not None and (type(serial) is not int or not 1 <= serial <= 999999999999):
        raise ValueError('Serial must be a positive integer up to twelve digits')
    if config['capabilities'] != dict(search=False, cartDetection=False, cartUndo=False) or config.get('cart') is not None:
        raise ValueError('Registration accepts only disabled, manual-shopping drafts')
    if config.get('schemaVersion') != 2:
        raise ValueError('Manual registration drafts must use schema 2')
    resource = f'packages/ios/ListRunner/Resources/{store}.json'
    source = (root / NATIVE).read_text()
    if (root / resource).exists() or re.search(r'\b' + re.escape(store) + r'\b', source):
        raise ValueError('Store already registered; never overwrite an identity')
    # New stores need permanent identities, not a shared mutable sequence. Allocate
    # once at code generation, never at runtime. Existing identities stay intact.
    # Explicit serials remain available for reviewed conventions/compatibility.
    ids = ([f'{prefix}0000000-0000-4000-8000-{serial:012d}' for prefix in ('1', '2')]
           if serial is not None else [str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()])
    if any(identity in source for identity in ids):
        raise ValueError('Permanent identity serial is already reserved; choose explicitly after fetching latest branches')
    original_source = source
    source = once(source, '    var id: String { rawValue }', f'    case `{store}`\n')
    # Insert in the owning switch, before conditional test-only cases. Existing
    # identities, capabilities and exceptional host/login policies remain byte intact.
    values = {
        'displayName': swift_string(config['displayName']),
        # Disabled schema-2 drafts have no reviewed category yet. Generate an
        # explicit unknown rather than guessing a primary category for them.
        'defaultCategory': 'nil',
        'hosts': '[' + ', '.join(swift_string(host) for host in config['allowedHosts']) + ']',
        'dataDomain': swift_string(domain),
        'listID': 'value = ' + swift_string(ids[0]),
        'websiteDataID': 'value = ' + swift_string(ids[1]),
    }
    for name, value in values.items():
        pattern = re.compile(r'(    var ' + name + r':[^\n]+\n)(.*?)(?=    (?:var|func) |\n})', re.S)
        match = pattern.search(source)
        if not match or '        switch self {\n' not in match[2]:
            raise ValueError(f'Native {name} layout changed; review generator')
        body = match[2]
        marker = '        #if STORE_REGISTRY_PROOF'
        body = once(body, marker, f'        case .`{store}`: {value}\n')
        source = source[:match.start(2)] + body + source[match.end(2):]
    source = once(source, '    var home: URL {\n', '')
    source = source.replace('    var home: URL {\n',
        f'    var home: URL {{\n        if self == .`{store}` {{ return URL(string: {swift_string(config["homepage"])})! }}\n', 1)
    color = config.get('addedColor', {})
    if set(color) != {'red', 'green', 'blue'} or any(type(value) is not int or not 0 <= value <= 255 for value in color.values()):
        raise ValueError('Brand color requires integer red/green/blue channels between 0 and 255')
    source = once(source, '                                        #if STORE_REGISTRY_PROOF',
        f'                                        case .`{store}`: AddedColor(red: {color["red"]}, green: {color["green"]}, blue: {color["blue"]})\n')
    project = (root / PROJECT).read_text()
    original_project = project
    reference = hashlib.sha256(f'listrunner:{store}:resource'.encode()).hexdigest()[:24].upper()
    build = hashlib.sha256(f'listrunner:{store}:build'.encode()).hexdigest()[:24].upper()
    if reference in project or build in project:
        raise ValueError('Xcode object identity collision')
    project = once(project, '/* End PBXBuildFile section */',
        f'\t\t{build} /* {store}.json in Resources */ = {{isa = PBXBuildFile; fileRef = {reference}; }};\n')
    project = once(project, '/* End PBXFileReference section */',
        f'\t\t{reference} /* {store}.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = ListRunner/Resources/{store}.json; sourceTree = SOURCE_ROOT; }};\n')
    # Anchor to the app resource phase, not the test target's phase.
    phase = re.search(r'(isa = PBXResourcesBuildPhase;.*?files = \(\n)', project, re.S)
    if len(re.findall('isa = PBXResourcesBuildPhase;', project)) != 1 or not phase:
        raise ValueError('Ambiguous resource phases; review project registration')
    project = project[:phase.end()] + f'\t\t\t\t{build} /* {store}.json in Resources */,\n' + project[phase.end():]
    group = '/* Begin PBXGroup section */'
    start = project.index(group)
    children = project.index('children = (\n', start) + len('children = (\n')
    project = project[:children] + f'\t\t\t\t{reference} /* {store}.json */,\n' + project[children:]
    return {NATIVE: (original_source, source), PROJECT: (original_project, project),
            resource: ('', json.dumps(config, indent=2, ensure_ascii=False) + '\n')}


def make_patch(files):
    return ''.join(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
        fromfile='a/' + path if before else '/dev/null', tofile='b/' + path))
        for path, (before, after) in files.items())


def resource_contract(project, store):
    """Check the selected resource's reference → build file → resource phase graph."""
    project = re.sub(r'/\*.*?\*/', '', project, flags=re.S)
    refs = re.findall(r'([A-F0-9]{24})\s*=\s*\{\s*isa\s*=\s*PBXFileReference;[^\n]*\bpath\s*=\s*"?(?:ListRunner/)?Resources/'
                      + re.escape(store) + r'\.json"?\s*;', project)
    if len(refs) != 1:
        return ['Selected store resource must have exactly one Xcode file reference']
    builds = re.findall(r'([A-F0-9]{24})\s*=\s*\{\s*isa\s*=\s*PBXBuildFile;\s*fileRef\s*=\s*'
                        + refs[0] + r'\s*;', project)
    phases = re.findall(r'isa\s*=\s*PBXResourcesBuildPhase;(.*?)\};', project, re.S)
    if len(builds) != 1 or sum(phase.count(builds[0]) for phase in phases) != 1:
        return ['Selected store resource must appear exactly once in Xcode resources']
    return []
