import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { AppleAPI, gh, ghJSON } from './beta-api.mjs';
import {
  appRelated, changedPaths, git, isAncestor, melbourneClock, notesForRange, readRequest,
  readyBuild, releaseMetadata, selectRun, verifyRun, MARKER, REQUEST_PREFIX,
} from './beta-policy.mjs';

const configPath = fileURLToPath(new URL('../nightly-beta.json', import.meta.url));

export function loadConfig() {
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  for (const key of ['repository', 'appId', 'workflowId', 'scmRepositoryId', 'bootstrapSha']) {
    if (typeof config[key] !== 'string' || !config[key]) throw new Error(`Missing beta configuration: ${key}`);
  }
  if (config.repository !== 'adriangith/listrunner') throw new Error('Unexpected release repository');
  return config;
}

export function cloudNotes(env = process.env, outputPath = fileURLToPath(new URL('../TestFlight/WhatToTest.en-US.txt', import.meta.url))) {
  const canonical = env.CI_GIT_REF ?? (env.CI_TAG ? `refs/tags/${env.CI_TAG}` : '');
  if (!canonical.startsWith(`refs/tags/${REQUEST_PREFIX}`)) {
    console.log('Not a managed nightly request; retaining curated tester notes.');
    return false;
  }
  const tag = canonical.slice('refs/tags/'.length);
  // Fetch exactly one immutable tag, not a moving branch or an unbounded log.
  if (!/^nightly\/request-\d{4}-\d{2}-\d{2}$/.test(tag)) throw new Error('Invalid CI request ref');
  git(['fetch', 'origin', `${canonical}:${canonical}`]);
  const request = readRequest(tag);
  const head = git(['rev-parse', 'HEAD']).trim();
  if (head !== request.sourceSha || env.CI_COMMIT !== request.sourceSha) {
    throw new Error('Refusing notes for a different source revision');
  }
  writeFileSync(outputPath, request.notes);
  console.log(`Generated nightly tester notes for ${head.slice(0, 12)}.`);
  return true;
}

export class NightlyBeta {
  constructor(config, api = new AppleAPI(), github = { gh, ghJSON }) {
    this.config = config;
    this.api = api;
    this.repoPath = `repos/${config.repository}`;
    this.submittedRequests = new Set();
    this.github = github;
  }

  releases() {
    return this.github.ghJSON(['--paginate', '--slurp', `${this.repoPath}/releases?per_page=100`]).flat();
  }

  baseline(releases) {
    const published = releases.map(release => ({ release, meta: releaseMetadata(release) }))
      .filter(value => value.meta)
      .sort((a, b) => new Date(b.release.published_at) - new Date(a.release.published_at));
    for (const { release, meta } of published) {
      const target = git(['rev-parse', `refs/tags/${release.tag_name}^{commit}`]).trim();
      if (target !== meta.sourceSha) throw new Error('Release tag/provenance mismatch');
    }
    return published[0]?.meta.sourceSha ?? this.config.bootstrapSha;
  }

  async preflight() {
    const workflow = (await this.api.request(`/v1/ciWorkflows/${this.config.workflowId}`)).data;
    const a = workflow.attributes;
    if (!a.isEnabled || a.scheduledStartCondition || a.branchStartCondition || a.tagStartCondition || a.pullRequestStartCondition) {
      throw new Error('Cloud workflow must be enabled and manual-only; disable competing automatic start conditions first');
    }
    const repository = (await this.api.request(`/v1/ciWorkflows/${workflow.id}/repository`)).data;
    if (repository.id !== this.config.scmRepositoryId
        || `${repository.attributes.ownerName}/${repository.attributes.repositoryName}` !== this.config.repository) {
      throw new Error('Xcode Cloud repository identity mismatch');
    }
    const app = (await this.api.request(`/v1/apps/${this.config.appId}`)).data;
    if (app.attributes.bundleId !== 'com.adrianzafir.listrunner') throw new Error('App identity mismatch');
    if (!a.clean || !a.manualTagStartCondition || !a.actions.some(action => action.actionType === 'ARCHIVE'
        && action.scheme === 'ListRunner' && action.buildDistributionAudience === 'APP_STORE_ELIGIBLE')) {
      throw new Error('Expected clean, App Store-eligible archive with manual tag starts enabled');
    }
  }

  async reference(tag) {
    const refs = await this.api.all(`/v1/scmRepositories/${this.config.scmRepositoryId}/gitReferences?limit=200`);
    const found = refs.filter(ref => ref.attributes.canonicalName === `refs/tags/${tag}` && !ref.attributes.isDeleted);
    if (found.length > 1) throw new Error('Ambiguous Apple source reference');
    return found[0];
  }

  async runs() {
    return this.api.all(`/v1/ciWorkflows/${this.config.workflowId}/buildRuns?include=sourceBranchOrTag&limit=200`);
  }

  async localize(buildId, notes) {
    const existing = (await this.api.all(`/v1/builds/${buildId}/betaBuildLocalizations?limit=200`))
      .find(value => value.attributes.locale === 'en-US');
    if (existing?.attributes.whatsNew === notes) return;
    if (existing) {
      await this.api.request(`/v1/betaBuildLocalizations/${existing.id}`, {
        method: 'PATCH', data: { type: 'betaBuildLocalizations', id: existing.id, attributes: { whatsNew: notes } },
      });
    } else {
      await this.api.request('/v1/betaBuildLocalizations', {
        method: 'POST', data: { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: notes },
          relationships: { build: { data: { type: 'builds', id: buildId } } } },
      });
    }
  }

  async publish(request, run) {
    verifyRun(run, request);
    const builds = await this.api.all(`/v1/ciBuildRuns/${run.id}/builds?limit=200`);
    if (builds.length === 0) return 'pending'; // Upload may become visible later.
    if (builds.length !== 1) throw new Error('Expected exactly one iOS upload for this workflow');
    const build = readyBuild(await this.api.request(`/v1/builds/${builds[0].id}?include=app,preReleaseVersion`), this.config.appId);
    if (!build) return 'pending';
    await this.localize(build.id, request.notes);
    const tag = `beta/ios-${build.version}-${build.build}`;
    const previous = this.releases().find(value => value.tag_name === tag);
    if (previous) {
      const meta = releaseMetadata(previous);
      if (meta?.sourceSha !== request.sourceSha || meta.buildId !== build.id || meta.requestTag !== request.tag) {
        throw new Error('Existing release conflicts with this build; refusing to overwrite');
      }
      return 'released';
    }
    const meta = { sourceSha: request.sourceSha, requestTag: request.tag, buildId: build.id, runId: run.id };
    const body = `${request.notes}\nTestFlight: **${build.version} (${build.build})**\n\n`
      + `Uploaded and processed successfully. External access may still require Apple beta review.\n\n`
      + `Changes: https://github.com/${this.config.repository}/compare/${request.baseSha}...${request.sourceSha}\n\n`
      + `<!-- ${MARKER} ${JSON.stringify(meta)} -->\n`;
    this.github.gh(['release', 'create', tag, '--repo', this.config.repository, '--target', request.sourceSha,
      '--prerelease', '--latest=false', '--title', `ListRunner ${build.version} (${build.build}) beta`, '--notes-file', '-'], { input: body });
    console.log(`Published beta prerelease ${tag} for ${request.sourceSha.slice(0, 12)}.`);
    return 'released';
  }

  async reconcile(request, { allowStart = true } = {}) {
    if (request.workflowId !== this.config.workflowId) throw new Error('Request belongs to another workflow');
    const reference = await this.reference(request.tag);
    if (!reference) return 'indexing';
    const run = selectRun(await this.runs(), reference.id);
    if (!run) {
      if (this.submittedRequests.has(request.tag)) return 'pending';
      if (!allowStart) return 'unstarted';
      // Never retry this POST blindly: a lost response is recovered by matching
      // the immutable source reference on the next invocation.
      await this.api.request('/v1/ciBuildRuns', { method: 'POST', data: {
        type: 'ciBuildRuns', attributes: { clean: true }, relationships: {
          workflow: { data: { type: 'ciWorkflows', id: this.config.workflowId } },
          sourceBranchOrTag: { data: { type: 'scmGitReferences', id: reference.id } },
        },
      } });
      this.submittedRequests.add(request.tag);
      console.log(`Started Xcode Cloud for ${request.tag}.`);
      return 'pending';
    }
    // Apple can expose the queued run before resolving its source commit.
    // Wait for that metadata; never publish without subsequently verifying it.
    if (!run.attributes.sourceCommit?.commitSha && run.attributes.executionProgress !== 'COMPLETE') return 'pending';
    verifyRun(run, request);
    if (run.attributes.executionProgress !== 'COMPLETE') return 'pending';
    if (run.attributes.completionStatus !== 'SUCCEEDED') {
      console.log(`Cloud build ${run.attributes.number} did not succeed; no GitHub release or baseline change.`);
      return 'failed';
    }
    return this.publish(request, run);
  }

  requests() {
    return git(['tag', '--list', `${REQUEST_PREFIX}*`]).trim().split('\n').filter(Boolean).sort().map(readRequest);
  }

  async wait(request) {
    const deadline = Date.now() + 140 * 60_000;
    let submitted = false;
    while (Date.now() < deadline) {
      const state = await this.reconcile(request, { allowStart: !submitted });
      if (state === 'released') return;
      if (state === 'failed') throw new Error('Cloud run failed; will retry the unreleased changes next night');
      if (state === 'pending') submitted = true;
      // Polling exists only inside the bounded CI job; the next job can recover
      // the durable request if this runner is cancelled or times out.
      await delay(30_000);
    }
    throw new Error('Timed out waiting for Apple; request retained for reconciliation next run');
  }

  async run({ plan = false, now = new Date() } = {}) {
    if (process.env.GITHUB_REPOSITORY && process.env.GITHUB_REPOSITORY !== this.config.repository) throw new Error('Unexpected GitHub repository');
    if (process.env.GITHUB_REF && process.env.GITHUB_REF !== 'refs/heads/main') throw new Error('Automation is allowed only from main');
    const clock = melbourneClock(now);
    if (process.env.GITHUB_EVENT_NAME === 'schedule' && clock.hour !== 2) {
      console.log('Not the Melbourne nightly window; skipping the alternate DST cron slot.');
      return;
    }
    const releases = this.releases();
    const baseline = this.baseline(releases);
    const target = git(['rev-parse', 'HEAD']).trim();
    const paths = changedPaths(baseline, target).filter(appRelated);
    console.log(`Baseline ${baseline.slice(0, 12)}; target ${target.slice(0, 12)}; app-related changed files: ${paths.length}.`);
    if (plan) {
      if (paths.length) console.log(notesForRange(baseline, target));
      return;
    }
    await this.preflight();
    const releasedTags = new Set(releases.map(releaseMetadata).filter(Boolean).map(meta => meta.requestTag));
    // Recover an earlier pending upload before considering any newer source.
    for (const request of this.requests()) {
      if (releasedTags.has(request.tag)) continue;
      if (isAncestor(request.sourceSha, baseline)) continue; // Already included in a newer release.
      if (!isAncestor(request.sourceSha, target)) throw new Error('Unreleased request is no longer on main; review it manually');
      const state = await this.reconcile(request);
      if (state === 'indexing' || state === 'pending') { await this.wait(request); return; }
      if (state === 'released') return;
    }
    if (!paths.length) { console.log('No app-related changes; no Cloud build or GitHub release.'); return; }
    const tag = `${REQUEST_PREFIX}${clock.date}`;
    if (this.requests().some(request => request.tag === tag)) {
      console.log('Today’s nightly request already exists; no duplicate build. Failed work remains eligible tomorrow.');
      return;
    }
    const request = { schema: 1, sourceSha: target, baseSha: baseline, workflowId: this.config.workflowId,
      notes: notesForRange(baseline, target) };
    git(['tag', '-a', tag, target, '-F', '-'], { input: JSON.stringify(request) + '\n' });
    git(['push', 'origin', `refs/tags/${tag}`]);
    console.log(`Pinned immutable nightly source ${tag}.`);
    await this.wait(readRequest(tag));
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const command = process.argv[2];
    if (command === 'cloud-notes') cloudNotes();
    else if (command === 'plan' || command === 'run') await new NightlyBeta(loadConfig()).run({ plan: command === 'plan' });
    else throw new Error('Usage: nightly-beta.mjs plan|run|cloud-notes');
  } catch (error) {
    console.error(`Nightly beta stopped: ${error.message}`);
    process.exitCode = 1;
  }
}
