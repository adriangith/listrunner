import { execFileSync } from 'node:child_process';

export const REQUEST_PREFIX = 'nightly/request-';
export const RELEASE_PREFIX = 'beta/ios-';
export const MARKER = 'listrunner-beta-v1';
export const shaPattern = /^[a-f0-9]{40}$/;

export function git(args, options = {}) {
  return execFileSync('git', args, { encoding: 'utf8', ...options });
}

// Exclude prose and tester notes, but include native tests/resource tooling:
// those checks are part of the archive gate and can change whether it builds.
export function appRelated(path) {
  if (path.endsWith('.md') || path.startsWith('packages/ios/TestFlight/')) return false;
  return path.startsWith('packages/ios/') || path === '.github/workflows/nightly-beta.yml';
}

export function changedPaths(base, target) {
  if (!shaPattern.test(base) || !shaPattern.test(target)) throw new Error('Expected full Git commit IDs');
  git(['merge-base', '--is-ancestor', base, target]);
  return git(['diff', '--name-only', '--no-renames', '-z', base, target]).split('\0').filter(Boolean);
}

export function isAncestor(base, target) {
  if (!shaPattern.test(base) || !shaPattern.test(target)) throw new Error('Expected full commit IDs');
  try { git(['merge-base', '--is-ancestor', base, target]); return true; }
  catch (error) { if (error.status === 1) return false; throw error; }
}

export function melbourneClock(now = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Australia/Melbourne', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', hourCycle: 'h23',
  }).formatToParts(now).map(part => [part.type, part.value]));
  return { date: `${parts.year}-${parts.month}-${parts.day}`, hour: Number(parts.hour) };
}

export function category(subject) {
  if (/^feat(?:\([^)]*\))?!?:/i.test(subject)) return 'Features';
  if (/^fix(?:\([^)]*\))?!?:/i.test(subject)) return 'Fixes';
  if (/^(?:docs|test|tests|chore|ci|build)(?:\([^)]*\))?!?:/i.test(subject)) return 'Build and reliability';
  return 'Improvements';
}

export function renderNotes(commits) {
  const sections = new Map();
  for (const { subject } of commits) {
    const group = category(subject);
    if (group === 'Build and reliability') {
      sections.set(group, new Set(['Build and automated-check improvements.']));
      continue;
    }
    const text = subject.replace(/^[a-z]+(?:\([^)]*\))?!?:\s*/i, '')
      .replace(/[\r\n\x00-\x1f<>]/g, ' ').trim().slice(0, 220);
    if (text) {
      if (!sections.has(group)) sections.set(group, new Set());
      sections.get(group).add(text);
    }
  }
  let result = 'Changes since the last released beta:\n';
  for (const name of ['Features', 'Fixes', 'Improvements', 'Build and reliability']) {
    const items = sections.get(name);
    if (!items) continue;
    result += `\n${name}\n${[...items].map(text => `• ${text}`).join('\n')}\n`;
  }
  if (!sections.size) result += '\nApp and build improvements.\n';
  const footer = '\nPlease report unexpected behaviour or regressions.\n';
  // Leave room for truncation text and stay below TestFlight’s 4,000 limit.
  if (result.length > 3650) result = result.slice(0, 3600) + '\n…More changes are listed in the GitHub comparison.\n';
  return result + footer;
}

export function notesForRange(base, target) {
  changedPaths(base, target); // Also verifies ancestry; never silently reset it.
  const commits = [];
  for (const line of git(['log', '--no-merges', '--format=%H', `${base}..${target}`]).trim().split('\n').filter(Boolean).reverse()) {
    const paths = git(['diff-tree', '--root', '--no-commit-id', '--name-only', '--no-renames', '-r', '-z', line]).split('\0');
    if (paths.some(appRelated)) commits.push({ subject: git(['show', '-s', '--format=%s', line]).trim() });
  }
  return renderNotes(commits);
}

export function validateRequest(value, tag, peeledSha) {
  if (value?.schema !== 1 || !/^nightly\/request-\d{4}-\d{2}-\d{2}$/.test(tag)
      || !shaPattern.test(value.sourceSha ?? '') || !shaPattern.test(value.baseSha ?? '')
      || value.sourceSha !== peeledSha || typeof value.workflowId !== 'string'
      || typeof value.notes !== 'string' || !value.notes.trim() || value.notes.length > 4000
      || value.notes.includes('<!-- listrunner-beta-v1')) {
    throw new Error(`Invalid immutable nightly request: ${tag}`);
  }
  if (value.recoveryOf !== undefined && (!/^nightly\/request-\d{4}-\d{2}-\d{2}$/.test(value.recoveryOf)
      || value.recoveryOf >= tag)) throw new Error('Recovery must reference an earlier nightly request');
  return { ...value, tag };
}

export function activeRequests(requests) {
  const byTag = new Map(requests.map(request => [request.tag, request]));
  const replaced = new Set();
  const replacements = new Set();
  for (const request of requests) {
    if (!request.recoveryOf) continue;
    const original = byTag.get(request.recoveryOf);
    if (!original || request.recoveryOf >= request.tag
        || ['schema', 'sourceSha', 'baseSha', 'workflowId', 'notes'].some(key => request[key] !== original[key])) {
      throw new Error('Recovery request does not preserve the original source, baseline, workflow and notes');
    }
    if (replacements.has(request.recoveryOf)) throw new Error('Ambiguous recovery requests; review manually');
    replacements.add(request.recoveryOf);
    replaced.add(request.recoveryOf);
  }
  return requests.filter(request => !replaced.has(request.tag));
}

export function ensureReleaseTag(tag, sourceSha) {
  if (!/^beta\/ios-[\d.]+-[\d.]+$/.test(tag) || !shaPattern.test(sourceSha)) throw new Error('Invalid beta release tag or source');
  const ref = `refs/tags/${tag}`;
  const remoteTarget = () => {
    const rows = git(['ls-remote', '--tags', 'origin', ref, `${ref}^{}`]).trim().split('\n').filter(Boolean)
      .map(line => line.split(/\s+/));
    return rows.find(([, name]) => name === `${ref}^{}`)?.[0]
      ?? rows.find(([, name]) => name === ref)?.[0];
  };
  const existing = remoteTarget();
  if (existing) {
    if (existing !== sourceSha) throw new Error('Remote beta tag conflicts with the verified source; refusing to overwrite');
    return;
  }
  if (git(['tag', '--list', tag]).trim()) {
    if (git(['rev-parse', `${ref}^{commit}`]).trim() !== sourceSha) throw new Error('Local beta tag conflicts with the verified source');
  } else {
    git(['tag', tag, sourceSha]);
  }
  // Git-first avoids implicit tag creation by the releases API, but GitHub may
  // still require Workflows permission for a historical workflow version.
  try {
    git(['push', 'origin', ref]);
  } catch (error) {
    if (/without [`'"]?workflows[`'"]? permission/i.test(String(error.stderr ?? error.message))) {
      throw new Error(`GitHub requires Workflows permission to tag this historical source. The verified TestFlight upload is retained. `
        + `Using a trusted user login with that permission, create/push ${tag} at ${sourceSha}, without overwriting any existing tag. `
        + 'Then rerun Nightly TestFlight beta in run mode to reuse the upload; no rebuild or broader CI token is needed.');
    }
    throw error;
  }
  if (remoteTarget() !== sourceSha) throw new Error('Published beta tag source could not be verified');
}

export function readRequest(tag) {
  if (!/^nightly\/request-\d{4}-\d{2}-\d{2}$/.test(tag)) throw new Error('Invalid nightly request tag');
  const ref = `refs/tags/${tag}`;
  const type = git(['cat-file', '-t', ref]).trim();
  if (type !== 'tag') throw new Error('Nightly requests must be annotated immutable tags');
  return validateRequest(JSON.parse(git(['for-each-ref', '--format=%(contents)', ref])), tag,
    git(['rev-parse', `${ref}^{commit}`]).trim());
}

export function releaseMetadata(release) {
  if (release.draft || !release.prerelease || !release.tag_name.startsWith(RELEASE_PREFIX)) return null;
  const match = release.body?.match(/<!-- listrunner-beta-v1 (\{[^\n]*\}) -->/);
  if (!match) throw new Error(`Automated release has no provenance: ${release.tag_name}`);
  const value = JSON.parse(match[1]);
  if (!shaPattern.test(value.sourceSha ?? '') || typeof value.requestTag !== 'string'
      || !value.buildId || !value.runId) throw new Error('Invalid release provenance');
  return value;
}

export function selectRun(runs, referenceId) {
  // More than one run is possible after an explicit human rebuild. Prefer a
  // successful run, then an in-progress run, then the most recent failure.
  const rank = run => run.attributes.completionStatus === 'SUCCEEDED' ? 2
    : run.attributes.executionProgress !== 'COMPLETE' ? 1 : 0;
  return runs.filter(run => run.relationships?.sourceBranchOrTag?.data?.id === referenceId)
    .sort((a, b) => rank(b) - rank(a) || b.attributes.number - a.attributes.number)[0];
}

export function verifyRun(run, request) {
  if (run.attributes.sourceCommit?.commitSha !== request.sourceSha || run.attributes.isPullRequestBuild) {
    throw new Error('Cloud build does not match the pinned source commit');
  }
}

export function readyBuild(response, appId) {
  const build = response.data;
  const app = response.included?.find(value => value.type === 'apps' && value.id === appId);
  const version = response.included?.find(value => value.type === 'preReleaseVersions'
    && value.id === build.relationships?.preReleaseVersion?.data?.id);
  if (!app || build.relationships?.app?.data?.id !== appId || !version
      || !/^[\d.]+$/.test(build.attributes.version) || !/^[\d.]+$/.test(version.attributes.version)) {
    throw new Error('Uploaded build identity/version could not be verified');
  }
  if (build.attributes.expired || ['FAILED', 'INVALID'].includes(build.attributes.processingState)) {
    throw new Error('Uploaded TestFlight build is expired or invalid');
  }
  if (build.attributes.processingState !== 'VALID') return null;
  return { id: build.id, build: build.attributes.version, version: version.attributes.version };
}
