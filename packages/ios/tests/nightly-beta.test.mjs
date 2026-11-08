import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { generateKeyPairSync, verify } from 'node:crypto';
import { AppleAPI, normalizePrivateKey } from '../tools/beta-api.mjs';
import { NightlyBeta, cloudNotes } from '../tools/nightly-beta.mjs';
import {
  activeRequests, appRelated, changedPaths, ensureReleaseTag, git, isAncestor, melbourneClock, notesForRange, readyBuild,
  releaseMetadata, renderNotes, selectRun, validateRequest, verifyRun,
} from '../tools/beta-policy.mjs';

const sha = 'a'.repeat(40);
const other = 'b'.repeat(40);
const config = { repository: 'adriangith/listrunner', appId: 'app', workflowId: 'workflow', scmRepositoryId: 'repo', bootstrapSha: sha };
const request = { schema: 1, sourceSha: sha, baseSha: other, workflowId: 'workflow', notes: 'Features\n• A new feature\n', tag: 'nightly/request-2026-11-05' };
const run = (status, ref = 'ref', number = 1) => ({ id: `run-${number}`, attributes: {
  sourceCommit: { commitSha: sha }, executionProgress: status ? 'COMPLETE' : 'RUNNING',
  completionStatus: status, number,
}, relationships: { sourceBranchOrTag: { data: { id: ref } } } });
const upload = (state = 'VALID') => ({ data: { id: 'build', attributes: { version: '6', expired: false, processingState: state },
  relationships: { app: { data: { id: 'app' } }, preReleaseVersion: { data: { id: 'version' } } } },
included: [{ type: 'apps', id: 'app' }, { type: 'preReleaseVersions', id: 'version', attributes: { version: '1.0' } }] });

function temporaryRepo(t) {
  const previous = process.cwd();
  const root = mkdtempSync(join(tmpdir(), 'listrunner-beta-test-'));
  process.chdir(root);
  t.after(() => { process.chdir(previous); rmSync(root, { recursive: true, force: true }); });
  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.name', 'Beta Test']); git(['config', 'user.email', 'beta-test@example.invalid']);
  mkdirSync('packages/ios', { recursive: true });
  writeFileSync('packages/ios/app.swift', 'initial');
  git(['add', '.']); git(['commit', '-qm', 'feat: initial app']);
  const base = git(['rev-parse', 'HEAD']).trim();
  const remote = join(root, 'remote.git');
  git(['init', '--bare', '-q', remote]); git(['remote', 'add', 'origin', remote]);
  git(['push', '-q', 'origin', 'main']);
  return { root, base, commit(path, text, subject) {
    writeFileSync(path, text); git(['add', path]); git(['commit', '-qm', subject]);
    return git(['rev-parse', 'HEAD']).trim();
  } };
}

test('app-related allowlist excludes docs, website and generated notes', () => {
  for (const path of ['packages/ios/ListRunner/App.swift', 'packages/ios/ListRunner/Assets.xcassets/a.png',
    'packages/ios/ListRunner.xcodeproj/project.pbxproj', 'packages/ios/tests/a.mjs',
    'packages/ios/ci_scripts/ci_post_clone.sh', '.github/workflows/nightly-beta.yml']) assert.ok(appRelated(path), path);
  for (const path of ['README.md', 'plan.md', 'website/index.html', 'packages/ios/VALIDATION.md',
    'packages/ios/TestFlight/WhatToTest.en-US.txt', '.github/workflows/website.yml']) assert.equal(appRelated(path), false, path);
});

test('Melbourne winter/summer cron slots and midnight boundary', () => {
  assert.deepEqual(melbourneClock(new Date('2026-11-04T15:07:00Z')), { date: '2026-11-05', hour: 2 });
  assert.equal(melbourneClock(new Date('2026-11-04T16:07:00Z')).hour, 3);
  assert.deepEqual(melbourneClock(new Date('2026-06-04T16:07:00Z')), { date: '2026-06-05', hour: 2 });
  assert.equal(melbourneClock(new Date('2026-06-04T15:07:00Z')).hour, 1);
});

test('notes group features/fixes, deduplicate maintenance and fit TestFlight', () => {
  const notes = renderNotes([{ subject: 'feat(ios): named grocery lists' }, { subject: 'fix: keyboard overlap' },
    { subject: 'ci: improve gates' }, { subject: 'test: add coverage' }, { subject: 'Improve scrolling' }]);
  assert.match(notes, /Features\n• named grocery lists/);
  assert.match(notes, /Fixes\n• keyboard overlap/);
  assert.match(notes, /Improvements\n• Improve scrolling/);
  assert.equal(notes.match(/Build and automated-check improvements/g).length, 1);
  assert.ok(renderNotes(Array.from({ length: 200 }, (_, i) => ({ subject: `feat: ${i} ${'x'.repeat(300)}` }))).length <= 4000);
  assert.doesNotMatch(renderNotes([{ subject: 'feat: <!-- listrunner-beta-v1 {} -->' }]), /<!--/);
});

test('net diff skips reverted app work, and notes exclude unrelated subjects', t => {
  const repo = temporaryRepo(t);
  const docs = repo.commit('README.md', 'docs', 'feat: unrelated website announcement');
  assert.equal(changedPaths(repo.base, docs).some(appRelated), false);
  const code = repo.commit('packages/ios/app.swift', 'changed', 'fix(ios): repair scrolling');
  const notes = notesForRange(repo.base, code);
  assert.match(notes, /repair scrolling/); assert.doesNotMatch(notes, /website announcement/);
  const reverted = repo.commit('packages/ios/app.swift', 'initial', 'revert app change');
  assert.equal(changedPaths(repo.base, reverted).some(appRelated), false);
  assert.ok(isAncestor(repo.base, reverted));
  assert.equal(isAncestor(reverted, repo.base), false);
  assert.throws(() => changedPaths(reverted, repo.base));
});

test('request provenance refuses moved tags, malformed SHAs, wrong refs and empty notes', () => {
  assert.equal(validateRequest(request, request.tag, sha).sourceSha, sha);
  for (const input of [{ ...request, sourceSha: other }, { ...request, baseSha: 'main' },
    { ...request, notes: '' }, { ...request, notes: 'x'.repeat(4001) }]) {
    assert.throws(() => validateRequest(input, request.tag, sha));
  }
  assert.throws(() => validateRequest(request, 'main', sha));
});

test('only owned, published beta prereleases advance the baseline', () => {
  const body = `<!-- listrunner-beta-v1 ${JSON.stringify({ sourceSha: sha, requestTag: request.tag, buildId: 'build', runId: 'run' })} -->`;
  const release = { tag_name: 'beta/ios-1.0-6', prerelease: true, draft: false, body };
  assert.equal(releaseMetadata(release).sourceSha, sha);
  assert.equal(releaseMetadata({ ...release, draft: true }), null);
  assert.equal(releaseMetadata({ ...release, prerelease: false }), null);
  assert.equal(releaseMetadata({ ...release, tag_name: 'unrelated-release' }), null);
  assert.throws(() => releaseMetadata({ ...release, body: '' }));
});

test('Cloud runs match exact source references and source commit, not just a green archive', () => {
  const failed = run('FAILED', 'ref', 3), pending = run(null, 'ref', 4), success = run('SUCCEEDED', 'ref', 2);
  assert.equal(selectRun([failed, pending, success, run('SUCCEEDED', 'other', 5)], 'ref'), success);
  assert.equal(selectRun([failed, pending], 'ref'), pending);
  verifyRun(success, request);
  assert.throws(() => verifyRun({ ...success, attributes: { ...success.attributes, sourceCommit: { commitSha: other } } }, request));
  assert.throws(() => verifyRun({ ...success, attributes: { ...success.attributes, isPullRequestBuild: true } }, request));
});

test('uploaded build must match app, version and successful processing', () => {
  assert.deepEqual(readyBuild(upload(), 'app'), { id: 'build', build: '6', version: '1.0' });
  assert.equal(readyBuild(upload('PROCESSING'), 'app'), null);
  assert.throws(() => readyBuild(upload('INVALID'), 'app'));
  assert.throws(() => readyBuild(upload('FAILED'), 'app'));
  assert.throws(() => readyBuild(upload(), 'wrong-app'));
  const expired = upload(); expired.data.attributes.expired = true;
  assert.throws(() => readyBuild(expired, 'app'));
});

test('failed Cloud run never localizes or creates a GitHub release', async () => {
  let writes = 0;
  const beta = new NightlyBeta(config, { request: async () => { writes++; } }, { gh: () => { writes++; } });
  beta.reference = async () => ({ id: 'ref' }); beta.runs = async () => [run('FAILED')];
  assert.equal(await beta.reconcile(request), 'failed');
  assert.equal(writes, 0);
});

test('an accepted start is not submitted twice while Apple indexing catches up', async () => {
  let starts = 0;
  const beta = new NightlyBeta(config, { request: async (path, options) => {
    assert.equal(path, '/v1/ciBuildRuns'); assert.equal(options.method, 'POST'); starts++;
    assert.equal(options.data.relationships.sourceBranchOrTag.data.id, 'ref');
  } });
  beta.reference = async () => ({ id: 'ref' }); beta.runs = async () => [];
  assert.equal(await beta.reconcile(request), 'pending');
  assert.equal(await beta.reconcile(request), 'pending');
  assert.equal(starts, 1);
});

test('ambiguous start failure aborts instead of blindly retrying POST', async () => {
  let starts = 0;
  const beta = new NightlyBeta(config, { request: async () => { starts++; throw new Error('network result unknown'); } });
  beta.reference = async () => ({ id: 'ref' }); beta.runs = async () => [];
  await assert.rejects(beta.reconcile(request), /unknown/);
  assert.equal(starts, 1);
  // A new runner recovers a previously accepted run via the immutable tag.
  beta.runs = async () => [run(null)];
  assert.equal(await beta.reconcile(request), 'pending');
  assert.equal(starts, 1);
});

test('queued runs may await source metadata, but completed runs must prove their SHA', async () => {
  const beta = new NightlyBeta(config, { request: async () => assert.fail('Do not start another run') });
  const queued = run(null); delete queued.attributes.sourceCommit;
  beta.reference = async () => ({ id: 'ref' }); beta.runs = async () => [queued];
  assert.equal(await beta.reconcile(request), 'pending');
  queued.attributes.executionProgress = 'COMPLETE'; queued.attributes.completionStatus = 'SUCCEEDED';
  await assert.rejects(beta.reconcile(request), /pinned source/);
});

test('publish waits for processing then emits only a prerelease for the pinned SHA', async () => {
  let processing = true, localizations = 0;
  const published = [];
  const api = {
    all: async path => path.includes('betaBuildLocalizations') ? [] : [{ id: 'build' }],
    request: async (path, options) => {
      if (path.startsWith('/v1/builds/')) return upload(processing ? 'PROCESSING' : 'VALID');
      assert.equal(options.data.relationships.build.data.id, 'build'); localizations++;
    },
  };
  const beta = new NightlyBeta(config, api, { gh: (args, options) => published.push({ args, options }) });
  const tags = [];
  beta.ensureReleaseTag = (tag, source) => tags.push({ tag, source });
  beta.releases = () => [];
  assert.equal(await beta.publish(request, run('SUCCEEDED')), 'pending');
  assert.equal(published.length, 0); assert.equal(localizations, 0);
  processing = false;
  assert.equal(await beta.publish(request, run('SUCCEEDED')), 'released');
  assert.equal(localizations, 1); assert.equal(published.length, 1);
  assert.ok(published[0].args.includes('--prerelease'));
  assert.deepEqual(tags, [{ tag: 'beta/ios-1.0-6', source: sha }]);
  assert.ok(published[0].args.includes('--verify-tag'));
  assert.ok(!published[0].args.includes('--target'));
  assert.match(published[0].options.input, /listrunner-beta-v1/);
});

test('no upload, failed processing and conflicting releases never publish', async () => {
  let writes = 0;
  const beta = new NightlyBeta(config, { all: async () => [], request: async () => upload() }, { gh: () => writes++ });
  assert.equal(await beta.publish(request, run('SUCCEEDED')), 'pending');
  beta.api.all = async () => [{ id: 'build' }];
  beta.localize = async () => {};
  beta.releases = () => [{ tag_name: 'beta/ios-1.0-6', draft: false, prerelease: true, body: 'unrelated release' }];
  await assert.rejects(beta.publish(request, run('SUCCEEDED')), /provenance/);
  beta.api.request = async () => upload('FAILED');
  await assert.rejects(beta.publish(request, run('SUCCEEDED')), /invalid/);
  assert.equal(writes, 0);
});

test('docs-only and unchanged nights do not create request tags or builds', async t => {
  const repo = temporaryRepo(t);
  repo.commit('README.md', 'documentation only', 'docs: improve instructions');
  let waited = 0;
  const beta = new NightlyBeta({ ...config, bootstrapSha: repo.base }, {});
  beta.releases = () => []; beta.preflight = async () => {}; beta.wait = async () => waited++;
  await beta.run();
  assert.equal(waited, 0); assert.equal(git(['tag', '--list']), '');
});

test('app changes pin once daily; failed changes retry the next night', async t => {
  const repo = temporaryRepo(t);
  const target = repo.commit('packages/ios/app.swift', 'fixed', 'fix(ios): improve import');
  const beta = new NightlyBeta({ ...config, bootstrapSha: repo.base }, {});
  beta.releases = () => []; beta.preflight = async () => {}; beta.reconcile = async () => 'failed';
  const requests = [];
  beta.wait = async value => { requests.push(value); };
  await beta.run({ now: new Date('2026-11-04T15:07:00Z') });
  assert.equal(requests.length, 1); assert.equal(requests[0].sourceSha, target);
  assert.match(requests[0].notes, /improve import/);
  await beta.run({ now: new Date('2026-11-04T15:30:00Z') });
  assert.equal(requests.length, 1);
  await beta.run({ now: new Date('2026-11-05T15:07:00Z') });
  assert.equal(requests.length, 2); assert.equal(requests[1].baseSha, repo.base);
});

test('plan mode has no Apple/tag/release mutations', async t => {
  const repo = temporaryRepo(t);
  repo.commit('packages/ios/app.swift', 'new feature', 'feat: named lists');
  const beta = new NightlyBeta({ ...config, bootstrapSha: repo.base }, {});
  beta.releases = () => []; beta.preflight = async () => { throw new Error('Unexpected Apple call'); };
  await beta.run({ plan: true });
  assert.equal(git(['tag', '--list']), '');
});

test('pending requests are recovered before creating a new nightly source', async t => {
  const repo = temporaryRepo(t);
  const first = repo.commit('packages/ios/app.swift', 'first', 'fix: first');
  const previous = { ...request, sourceSha: first, baseSha: repo.base };
  git(['tag', '-a', request.tag, first, '-F', '-'], { input: JSON.stringify(previous) });
  repo.commit('packages/ios/app.swift', 'second', 'feat: second');
  const beta = new NightlyBeta({ ...config, bootstrapSha: repo.base }, {});
  beta.releases = () => []; beta.preflight = async () => {}; beta.reconcile = async () => 'pending';
  let recovered;
  beta.wait = async value => { recovered = value; };
  await beta.run({ now: new Date('2026-11-05T15:07:00Z') });
  assert.equal(recovered.sourceSha, first);
  assert.equal(git(['tag', '--list', 'nightly/*']).trim(), request.tag);
});

test('a successful prerelease advances the baseline so documentation cannot repeat it', async t => {
  const repo = temporaryRepo(t);
  const source = repo.commit('packages/ios/app.swift', 'released', 'feat: released app');
  const tag = 'beta/ios-1.0-6'; git(['tag', tag, source]);
  repo.commit('README.md', 'docs after release', 'docs: describe release');
  const beta = new NightlyBeta({ ...config, bootstrapSha: repo.base }, {});
  beta.releases = () => [{ tag_name: tag, prerelease: true, draft: false, published_at: '2026-11-04T01:00:00Z',
    body: `<!-- listrunner-beta-v1 ${JSON.stringify({ sourceSha: source, requestTag: request.tag, buildId: 'build', runId: 'run' })} -->` }];
  beta.preflight = async () => {}; beta.wait = async () => assert.fail('No new release expected');
  await beta.run();
  assert.equal(git(['tag', '--list', 'nightly/*']).trim(), '');
});

test('preflight refuses competing schedules, wrong apps/repositories or non-distributable archives', async () => {
  const attributes = { isEnabled: true, clean: true, manualTagStartCondition: { source: { isAllMatch: true } },
    actions: [{ actionType: 'ARCHIVE', scheme: 'ListRunner', buildDistributionAudience: 'APP_STORE_ELIGIBLE' }] };
  const api = { request: async path => {
    if (path.endsWith('/repository')) return { data: { id: 'repo', attributes: { ownerName: 'adriangith', repositoryName: 'listrunner' } } };
    if (path.startsWith('/v1/apps/')) return { data: { attributes: { bundleId: 'com.adrianzafir.listrunner' } } };
    return { data: { id: 'workflow', attributes } };
  } };
  const beta = new NightlyBeta(config, api);
  await beta.preflight();
  attributes.scheduledStartCondition = { schedule: { hour: 2 } };
  await assert.rejects(beta.preflight(), /manual-only/);
  delete attributes.scheduledStartCondition;
  attributes.clean = false;
  await assert.rejects(beta.preflight(), /clean/);
  attributes.clean = true; attributes.actions[0].scheme = 'UnrelatedApp';
  await assert.rejects(beta.preflight(), /archive/);
});

test('cloud notes are recovered from the immutable request, never a moving branch', t => {
  const repo = temporaryRepo(t);
  const value = { ...request, sourceSha: repo.base, baseSha: repo.base };
  git(['tag', '-a', request.tag, repo.base, '-F', '-'], { input: JSON.stringify(value) });
  git(['push', '-q', 'origin', `refs/tags/${request.tag}`]);
  const path = join(repo.root, 'tester-notes.txt');
  assert.ok(cloudNotes({ CI_GIT_REF: `refs/tags/${request.tag}`, CI_COMMIT: repo.base }, path));
  assert.equal(readFileSync(path, 'utf8'), request.notes);
  assert.throws(() => cloudNotes({ CI_GIT_REF: `refs/tags/${request.tag}`, CI_COMMIT: sha }, path));
  assert.equal(cloudNotes({ CI_GIT_REF: 'refs/heads/main' }, path), false);
});

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
const credentials = { ASC_PRIVATE_KEY: pem, ASC_KEY_ID: 'test-key', ASC_ISSUER_ID: 'test-issuer' };

function diagnosticBeta(api = {}) {
  const lines = [];
  let now = 0;
  const beta = new NightlyBeta(config, api, { gh: () => assert.fail('Unexpected GitHub write') }, {
    now: () => now, sleep: async ms => { now += ms; }, log: line => lines.push(line),
  });
  beta.reference = async () => ({ id: 'ref' });
  beta.runs = async () => [];
  return { beta, lines, advance: ms => { now += ms; } };
}

test('inspect reports missing source references and never starts a build', async () => {
  const { beta } = diagnosticBeta({ request: async () => assert.fail('No Apple writes') });
  beta.reference = async () => undefined;
  beta.releases = () => []; beta.requests = () => [request];
  await beta.inspect();
  assert.equal(beta.diagnostic.stage, 'source-reference-not-indexed');
  assert.equal(beta.diagnostic.request, request.tag);
});

test('read-only inspection distinguishes an indexed reference with no run', async () => {
  const { beta } = diagnosticBeta({ request: async () => assert.fail('No starts') });
  assert.equal(await beta.reconcile(request, { readOnly: true }), 'unstarted');
  assert.equal(beta.diagnostic.stage, 'cloud-run-not-visible');
  assert.equal(beta.diagnostic.referenceId, 'ref');
});

test('diagnostics distinguish source metadata, execution and Cloud failure', async () => {
  const { beta } = diagnosticBeta();
  const queued = run(null); delete queued.attributes.sourceCommit;
  beta.runs = async () => [queued];
  await beta.reconcile(request, { readOnly: true });
  assert.equal(beta.diagnostic.stage, 'cloud-source-metadata');
  beta.runs = async () => [run(null)];
  await beta.reconcile(request, { readOnly: true });
  assert.equal(beta.diagnostic.stage, 'cloud-execution');
  assert.equal(beta.diagnostic.executionProgress, 'RUNNING');
  beta.runs = async () => [run('FAILED')];
  assert.equal(await beta.reconcile(request, { readOnly: true }), 'failed');
  assert.equal(beta.diagnostic.stage, 'cloud-failed');
  assert.equal(beta.diagnostic.runId, 'run-1');
});

test('read-only inspection distinguishes missing upload, processing and publication readiness', async () => {
  const { beta } = diagnosticBeta({ all: async () => [], request: async () => upload('PROCESSING') });
  beta.runs = async () => [run('SUCCEEDED')];
  beta.localize = async () => assert.fail('Do not change tester notes');
  await beta.reconcile(request, { readOnly: true });
  assert.equal(beta.diagnostic.stage, 'upload-not-visible');
  beta.api.all = async () => [{ id: 'build' }];
  await beta.reconcile(request, { readOnly: true });
  assert.equal(beta.diagnostic.stage, 'testflight-processing');
  assert.equal(beta.diagnostic.processingState, 'PROCESSING');
  beta.api.request = async () => upload();
  assert.equal(await beta.reconcile(request, { readOnly: true }), 'ready');
  assert.equal(beta.diagnostic.stage, 'ready-to-publish');
});

test('lookup errors preserve the exact failing operation without remote payloads', async () => {
  const { beta, lines } = diagnosticBeta();
  beta.reference = async () => { throw new Error('Apple API GET returned HTTP 500'); };
  await assert.rejects(beta.reconcile(request), /HTTP 500/);
  assert.equal(beta.diagnostic.stage, 'source-reference-lookup');
  assert.equal(lines.length, 0);
});

test('stable waiting status logs transitions and five-minute heartbeats, not every poll', async () => {
  const { beta, lines, advance } = diagnosticBeta();
  beta.reference = async () => undefined;
  await beta.reconcile(request);
  advance(30_000); await beta.reconcile(request);
  assert.equal(lines.length, 1);
  advance(270_000); await beta.reconcile(request);
  assert.equal(lines.length, 2);
  assert.match(lines[1], /"elapsedSeconds":300/);
  assert.doesNotMatch(lines.join('\n'), /PRIVATE KEY|Authorization/);
});

test('timeout identifies the retained request and last waiting stage without a real wait', async () => {
  const { beta } = diagnosticBeta();
  beta.reference = async () => undefined;
  await assert.rejects(beta.wait(request, { timeoutMs: 60_000 }), error => {
    assert.match(error.message, /Timed out waiting for Apple/);
    assert.match(error.message, /source-reference-not-indexed/);
    assert.match(error.message, /nightly\/request-2026-11-05/);
    return true;
  });
});

test('inspect skips published requests without applying the nightly time guard', async () => {
  const { beta } = diagnosticBeta();
  beta.releases = () => [{ tag_name: 'beta/ios-1.0-6', prerelease: true, draft: false,
    body: `<!-- listrunner-beta-v1 ${JSON.stringify({ sourceSha: sha, requestTag: request.tag, buildId: 'build', runId: 'run' })} -->` }];
  beta.requests = () => [request];
  beta.reconcile = async () => assert.fail('Already published');
  await beta.inspect();
});

test('recovery chains preserve provenance and select only the newest linked request', () => {
  const second = { ...request, tag: 'nightly/request-2026-11-06', recoveryOf: request.tag };
  const third = { ...request, tag: 'nightly/request-2026-11-07', recoveryOf: second.tag };
  assert.deepEqual(activeRequests([request, second, third]), [third]);
  for (const changes of [{ sourceSha: other }, { baseSha: sha }, { workflowId: 'other' }, { notes: 'changed' }]) {
    assert.throws(() => activeRequests([request, { ...second, ...changes }]), /preserve/);
  }
  assert.throws(() => activeRequests([second]), /preserve/);
  assert.throws(() => activeRequests([request, second, { ...third, recoveryOf: request.tag }]), /Ambiguous/);
  assert.throws(() => validateRequest({ ...request, recoveryOf: request.tag }, request.tag, sha), /earlier/);
  assert.throws(() => validateRequest({ ...request, recoveryOf: 'refs/heads/main' }, second.tag, sha), /earlier/);
});

test('release tags pin historical source through Git, are idempotent and never advance the baseline alone', t => {
  const repo = temporaryRepo(t);
  repo.commit('packages/ios/app.swift', 'newer', 'feat: newer main');
  ensureReleaseTag('beta/ios-1.0-7', repo.base);
  assert.equal(git(['rev-parse', 'beta/ios-1.0-7^{commit}']).trim(), repo.base);
  ensureReleaseTag('beta/ios-1.0-7', repo.base);
  const { beta } = diagnosticBeta();
  beta.config = { ...config, bootstrapSha: repo.base };
  assert.equal(beta.baseline([]), repo.base);
  assert.throws(() => ensureReleaseTag('beta/ios-1.0-7', git(['rev-parse', 'HEAD']).trim()), /Remote beta tag conflicts/);
  assert.equal(git(['rev-parse', 'beta/ios-1.0-7^{commit}']).trim(), repo.base);
});

test('release tag verification accepts matching annotated tags but refuses local conflicts', t => {
  const repo = temporaryRepo(t);
  git(['tag', '-a', 'beta/ios-1.0-7', repo.base, '-m', 'verified upload']);
  git(['push', 'origin', 'refs/tags/beta/ios-1.0-7']);
  ensureReleaseTag('beta/ios-1.0-7', repo.base);
  const newer = repo.commit('packages/ios/app.swift', 'newer', 'feat: newer work');
  git(['tag', 'beta/ios-1.0-8', newer]);
  assert.throws(() => ensureReleaseTag('beta/ios-1.0-8', repo.base), /Local beta tag conflicts/);
  assert.equal(git(['ls-remote', '--tags', 'origin', 'refs/tags/beta/ios-1.0-8']).trim(), '');
});

test('recovery creates a new immutable request without moving the original or using newer main', async t => {
  const repo = temporaryRepo(t);
  const original = { ...request, sourceSha: repo.base, baseSha: repo.base };
  git(['tag', '-a', request.tag, repo.base, '-F', '-'], { input: JSON.stringify(original) });
  const originalObject = git(['rev-parse', request.tag]).trim();
  repo.commit('packages/ios/app.swift', 'newer', 'feat: newer work');
  const { beta } = diagnosticBeta();
  const recovered = await beta.recoverUnindexed(original, '2026-11-06');
  assert.equal(recovered.recoveryOf, request.tag);
  assert.equal(recovered.sourceSha, repo.base);
  assert.equal(recovered.notes, original.notes);
  assert.equal(git(['rev-parse', request.tag]).trim(), originalObject);
  assert.equal(git(['rev-parse', `${recovered.tag}^{commit}`]).trim(), repo.base);
  assert.deepEqual(activeRequests(beta.requests()).map(value => value.tag), [recovered.tag]);
  await assert.rejects(beta.recoverUnindexed(original, '2026-11-06'), /already exists/);
});

test('recovery refuses same-day requests, orphaned runs and unresolved active runs', async t => {
  const repo = temporaryRepo(t);
  const original = { ...request, sourceSha: repo.base, baseSha: repo.base };
  git(['tag', '-a', request.tag, repo.base, '-F', '-'], { input: JSON.stringify(original) });
  const { beta } = diagnosticBeta();
  await assert.rejects(beta.recoverUnindexed(original, '2026-11-05'), /later Melbourne date/);
  beta.runs = async () => [{ ...run('SUCCEEDED'), attributes: { ...run('SUCCEEDED').attributes, sourceCommit: { commitSha: repo.base } } }];
  await assert.rejects(beta.recoverUnindexed(original, '2026-11-06'), /may already exist/);
  beta.runs = async () => [{ id: 'unresolved', attributes: { executionProgress: 'PENDING' } }];
  await assert.rejects(beta.recoverUnindexed(original, '2026-11-06'), /may already exist/);
  assert.equal(beta.requests().length, 1);
});

test('nightly run recovers an older unindexed request before considering newer main', async t => {
  const repo = temporaryRepo(t);
  const source = repo.commit('packages/ios/app.swift', 'pending', 'feat: pending work');
  const original = { ...request, sourceSha: source, baseSha: repo.base };
  git(['tag', '-a', request.tag, source, '-F', '-'], { input: JSON.stringify(original) });
  repo.commit('packages/ios/app.swift', 'newer', 'feat: newer work');
  const { beta } = diagnosticBeta();
  beta.config = { ...config, bootstrapSha: repo.base };
  beta.releases = () => []; beta.preflight = async () => {};
  beta.reference = async () => undefined;
  let waited;
  beta.wait = async value => { waited = value; };
  await beta.run({ now: new Date('2026-11-05T15:07:00Z') });
  assert.equal(waited.recoveryOf, request.tag);
  assert.equal(waited.sourceSha, source);
  assert.equal(waited.tag, 'nightly/request-2026-11-06');
});

test('nightly follows an existing recovery and never starts the replaced original', async t => {
  const repo = temporaryRepo(t);
  const source = repo.commit('packages/ios/app.swift', 'pending', 'feat: pending work');
  const original = { ...request, sourceSha: source, baseSha: repo.base };
  const recovery = { ...original, tag: 'nightly/request-2026-11-06', recoveryOf: request.tag };
  for (const value of [original, recovery]) git(['tag', '-a', value.tag, source, '-F', '-'], { input: JSON.stringify(value) });
  const { beta } = diagnosticBeta();
  beta.config = { ...config, bootstrapSha: repo.base };
  beta.releases = () => []; beta.preflight = async () => {};
  beta.reconcile = async value => { assert.equal(value.tag, recovery.tag); return 'pending'; };
  beta.wait = async value => { assert.equal(value.tag, recovery.tag); };
  await beta.run({ now: new Date('2026-11-06T15:07:00Z') });
});

test('inspection follows recovery metadata without attempting recovery mutations', async () => {
  const { beta } = diagnosticBeta();
  const recovery = { ...request, tag: 'nightly/request-2026-11-06', recoveryOf: request.tag };
  beta.requests = () => [request, recovery]; beta.releases = () => [];
  beta.recoverUnindexed = async () => assert.fail('Inspection cannot create a recovery');
  beta.reconcile = async (value, options) => {
    assert.equal(value.tag, recovery.tag);
    assert.deepEqual(options, { allowStart: false, readOnly: true });
    return 'indexing';
  };
  await beta.inspect();
});

test('inspect uses only GETs through the real API client even for a ready upload', async () => {
  const paths = [];
  const api = new AppleAPI(credentials, async (url, options) => {
    assert.equal(options.method, 'GET');
    paths.push(url.pathname);
    let body;
    if (url.pathname.endsWith('/gitReferences')) body = { data: [{ id: 'ref', attributes: { canonicalName: `refs/tags/${request.tag}` } }] };
    else if (url.pathname.endsWith('/buildRuns')) body = { data: [run('SUCCEEDED')] };
    else if (url.pathname.endsWith('/builds')) body = { data: [{ id: 'build' }] };
    else if (url.pathname === '/v1/builds/build') body = upload();
    else assert.fail(`Unexpected endpoint: ${url.pathname}`);
    return new Response(JSON.stringify(body));
  });
  const { beta } = diagnosticBeta(api);
  delete beta.reference; delete beta.runs;
  beta.releases = () => []; beta.requests = () => [request];
  await beta.inspect();
  assert.equal(beta.diagnostic.stage, 'ready-to-publish');
  assert.equal(paths.length, 4);
});

test('GitHub step summary records structured waiting status', t => {
  const directory = mkdtempSync(join(tmpdir(), 'listrunner-beta-summary-'));
  const previous = process.env.GITHUB_STEP_SUMMARY;
  const path = join(directory, 'summary.md');
  process.env.GITHUB_STEP_SUMMARY = path;
  t.after(() => {
    if (previous === undefined) delete process.env.GITHUB_STEP_SUMMARY;
    else process.env.GITHUB_STEP_SUMMARY = previous;
    rmSync(directory, { recursive: true, force: true });
  });
  const { beta } = diagnosticBeta();
  beta.progress(request, 'source-reference-not-indexed');
  assert.match(readFileSync(path, 'utf8'), /source-reference-not-indexed/);
  assert.match(readFileSync(path, 'utf8'), /nightly\/request-2026-11-05/);
});

test('Apple token is an expiring ES256 JWT and accepts a single-line private key', () => {
  const api = new AppleAPI({ ...credentials, ASC_PRIVATE_KEY: pem.replaceAll('\n', ' ') });
  const token = api.token(); const [header, payload, signature] = token.split('.');
  assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'ES256');
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.equal(claims.aud, 'appstoreconnect-v1'); assert.ok(claims.exp - claims.iat <= 1200);
  assert.ok(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
  assert.equal(normalizePrivateKey(pem.replaceAll('\n', '\\n')), normalizePrivateKey(pem));
});

test('Apple client refuses credential exfiltration, redirects, error bodies and pagination loops', async () => {
  let calls = 0;
  const api = new AppleAPI(credentials, async (_url, options) => {
    calls++; assert.equal(options.redirect, 'error');
    return new Response(JSON.stringify({ private: 'must-not-appear-in-error' }), { status: 403 });
  });
  await assert.rejects(api.request('https://evil.invalid/v1/builds'), /unexpected URL/);
  assert.equal(calls, 0);
  await assert.rejects(api.request('/v1/builds'), error => !error.message.includes('must-not-appear') && error.message.includes('403'));
  api.fetcher = async () => new Response(JSON.stringify({ data: [], links: { next: '/v1/builds' } }));
  await assert.rejects(api.all('/v1/builds'), /pagination loop/);
});
