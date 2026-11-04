import { createPrivateKey, sign } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

export function normalizePrivateKey(value) {
  const match = value.replaceAll('\\n', '\n').match(/-----BEGIN PRIVATE KEY-----([\s\S]*?)-----END PRIVATE KEY-----/);
  if (!match) throw new Error('A PEM App Store Connect private key is required');
  const encoded = match[1].replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/=]+$/.test(encoded)) throw new Error('Invalid private key encoding');
  return `-----BEGIN PRIVATE KEY-----\n${encoded.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
}

export class AppleAPI {
  constructor(env = process.env, fetcher = fetch) {
    this.issuerId = env.ASC_ISSUER_ID;
    this.keyId = env.ASC_KEY_ID;
    if (!this.issuerId || !this.keyId) throw new Error('Missing App Store Connect key identifiers');
    this.key = createPrivateKey(normalizePrivateKey(env.ASC_PRIVATE_KEY_FILE
      ? readFileSync(env.ASC_PRIVATE_KEY_FILE, 'utf8') : env.ASC_PRIVATE_KEY ?? ''));
    if (this.key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new Error('Expected an ES256 App Store Connect key');
    this.fetcher = fetcher;
  }

  token() {
    const now = Math.floor(Date.now() / 1000);
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const message = `${encode({ alg: 'ES256', kid: this.keyId, typ: 'JWT' })}.${encode({ iss: this.issuerId, iat: now - 10, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
    return `${message}.${sign('sha256', Buffer.from(message), { key: this.key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
  }

  async request(path, { method = 'GET', data } = {}) {
    const url = new URL(path, 'https://api.appstoreconnect.apple.com');
    if (url.origin !== 'https://api.appstoreconnect.apple.com' || !url.pathname.startsWith('/v1/')) {
      throw new Error('Refusing to send Apple credentials to an unexpected URL');
    }
    const response = await this.fetcher(url, {
      method, redirect: 'error', signal: AbortSignal.timeout(60_000),
      headers: { Authorization: `Bearer ${this.token()}`, 'Content-Type': 'application/json' },
      ...(data ? { body: JSON.stringify({ data }) } : {}),
    });
    if (!response.ok) {
      // Do not echo remote bodies, headers, or tokens into CI logs.
      throw new Error(`Apple API ${method} ${url.pathname} returned HTTP ${response.status}`);
    }
    return response.status === 204 ? {} : response.json();
  }

  async all(path) {
    const rows = [];
    const seen = new Set();
    while (path) {
      if (seen.has(path)) throw new Error('Apple pagination loop');
      seen.add(path);
      const page = await this.request(path);
      if (!Array.isArray(page.data)) throw new Error('Expected an Apple resource collection');
      rows.push(...page.data);
      path = page.links?.next;
    }
    return rows;
  }
}

export function gh(args, options = {}) {
  return execFileSync('gh', args, { encoding: 'utf8', ...options });
}

export function ghJSON(args, options) {
  return JSON.parse(gh(['api', ...args], options));
}
