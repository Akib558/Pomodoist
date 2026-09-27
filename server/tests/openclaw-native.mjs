// Full native setup against a disposable local server, with HTTP-only consent.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { parseEnv } from 'node:util';
import { randomUUID } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

assert.ok(process.argv.includes('--local'), 'Pass --local only for a disposable self-hosted test instance.');
const config = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const base = new URL(config.SUPABASE_PUBLIC_URL);
assert.ok(base.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)
  && base.port === '55421' && base.pathname === '/' && !base.username && !base.password && !base.search && !base.hash,
  'Only the disposable loopback HTTP :55421 stack is allowed.');
const endpoint = new URL('/functions/v1/pomodoist-mcp', base).href;
const cli = process.env.OPENCLAW_TEST_BIN || 'openclaw';
const state = mkdtempSync(join(tmpdir(), 'pomodoist-openclaw-'));
const env = { ...process.env, OPENCLAW_STATE_DIR: state,
  OPENCLAW_CONFIG_PATH: join(state, 'openclaw.json'), OPENCLAW_OAUTH_DIR: join(state, 'credentials'),
  PATH: cli.includes('/') ? `${dirname(cli)}:${process.env.PATH}` : process.env.PATH,
};
let userId;
let child;

async function request(path, { method = 'GET', token, body, status = 200 } = {}) {
  // A cold Deno Edge worker can exceed a short deadline on its first request, so
  // retry transport timeouts instead of reporting a false acceptance failure.
  let response;
  for (let attempt = 1; ; attempt++) {
    try {
      response = await fetch(new URL(path, base), { method, redirect: 'manual',
        headers: { apikey: config.ANON_KEY, ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30_000) });
      break;
    } catch (error) {
      if (attempt >= 3 || error.name !== 'TimeoutError') throw error;
      await new Promise(resolve => setTimeout(resolve, 1_000 * attempt));
    }
  }
  assert.ok(response.status === status, `${method} ${new URL(path, base).pathname}: HTTP ${response.status}, expected ${status}`);
  const text = await response.text();
  return { response, data: text && response.headers.get('content-type')?.includes('json') ? JSON.parse(text) : null };
}

function run(args, expected = 0) {
  const result = spawnSync(cli, args, { env, encoding: 'utf8', timeout: 60000 });
  const diagnostic = (result.stderr || '').slice(0, 500).replace(/[A-Za-z0-9_.-]{24,}/g, '[redacted]');
  assert.ok(!result.error && result.status === expected, `Native ${args.slice(0, 2).join(' ')} returned ${result.status}: ${diagnostic}`);
  return result.stdout;
}

try {
  const account = { email: `native-openclaw-${randomUUID()}@example.invalid`, password: randomUUID() + randomUUID() };
  userId = (await request('/auth/v1/signup', { method: 'POST', body: account })).data.user.id;
  const token = (await request('/auth/v1/token?grant_type=password', { method: 'POST', body: account })).data.access_token;
  run(['mcp', 'set', 'unrelated', JSON.stringify({ url: 'http://localhost:1/mcp', enabled: false })]);

  child = spawn(process.execPath, [fileURLToPath(new URL('../../tool/openclaw/configure.mjs', import.meta.url)), endpoint, '--write', '--apply'],
    { env, detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  let resolveUrl;
  let rejectUrl;
  const authorization = new Promise((resolve, reject) => { resolveUrl = resolve; rejectUrl = reject; });
  child.stdout.on('data', chunk => {
    output = (output + chunk).slice(-1024 * 1024);
    const url = output.match(/^https?:\/\/[^\s]+$/m)?.[0];
    if (url) resolveUrl(url);
  });
  // Never print CLI output: authorization codes/URLs may appear there.
  child.stderr.resume();
  child.once('error', () => rejectUrl(new Error('Native setup failed to start.')));
  const completed = new Promise(resolve => child.once('close', code => {
    rejectUrl(new Error('Native setup exited before returning an OAuth URL.'));
    resolve(code);
  }));
  const timeout = setTimeout(() => {
    rejectUrl(new Error('Native setup timed out.'));
    if (process.platform !== 'win32') { try { process.kill(-child.pid, 'SIGTERM'); } catch {} }
    else child.kill();
  }, 120000);
  try {
    const url = new URL(await authorization);
    assert.ok(url.origin === base.origin && url.pathname === '/auth/v1/oauth/authorize', 'Unexpected native authorization URL.');
    const redirect = new URL(url.searchParams.get('redirect_uri'));
    assert.ok(redirect.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(redirect.hostname), 'Callback must be loopback.');
    const { response } = await request(url, { status: 302 });
    const consentUrl = new URL(response.headers.get('location'));
    assert.ok(consentUrl.origin === new URL(config.SITE_URL).origin && consentUrl.pathname === '/oauth/consent', 'Unexpected consent URL.');
    const authorizationId = consentUrl.searchParams.get('authorization_id');
    assert.ok(authorizationId && /^[A-Za-z0-9_-]{1,200}$/.test(authorizationId), 'Missing authorization ID.');
    const details = (await request(`/auth/v1/oauth/authorizations/${authorizationId}`, { token })).data;
    assert.ok(details.user.id === userId && details.client.id === url.searchParams.get('client_id'), 'Consent identity mismatch.');
    const consent = (await request(`/auth/v1/oauth/authorizations/${authorizationId}/consent`,
      { method: 'POST', token, body: { action: 'approve' } })).data;
    const callback = new URL(consent.redirect_url);
    assert.ok(callback.origin === redirect.origin && callback.pathname === redirect.pathname
      && callback.searchParams.get('state') === url.searchParams.get('state') && callback.searchParams.has('code'), 'Invalid callback.');
    await request(callback);
    assert.ok(await completed === 0 && output.includes('Connected.'), 'Native setup/login/probe failed.');
  } finally { clearTimeout(timeout); }

  const saved = JSON.parse(run(['mcp', 'list', '--json']));
  assert.ok(saved.unrelated.enabled === false && saved.pomodoist.auth === 'oauth', 'Other configuration changed.');
  assert.ok(saved.pomodoist.toolFilter.include.includes('openclaw_focus')
    && !saved.pomodoist.toolFilter.include.includes('create_task'), 'Wrong native tool filter.');
  run(['mcp', 'doctor', 'pomodoist', '--probe']);
  const grants = (await request('/auth/v1/user/oauth/grants', { token })).data;
  assert.ok(grants.length === 1, 'Expected one synthetic native OAuth grant.');
  await request(`/auth/v1/user/oauth/grants?client_id=${grants[0].client.id}`, { method: 'DELETE', token, status: 204 });
  const revoked = spawnSync(cli, ['mcp', 'doctor', 'pomodoist', '--probe'], { env, encoding: 'utf8', timeout: 60000 });
  assert.ok(revoked.status !== null && revoked.status !== 0, 'Native probe succeeded after server revocation.');
  run(['mcp', 'logout', 'pomodoist']);
  run(['mcp', 'configure', 'pomodoist', '--disable']);
  assert.equal(JSON.parse(run(['mcp', 'list', '--json'])).pomodoist.enabled, false);
  const before = readFileSync(env.OPENCLAW_CONFIG_PATH, 'utf8');
  const removal = spawnSync(cli, ['mcp', 'unset', 'pomodoist'], { env, encoding: 'utf8', timeout: 60000 });
  if (!removal.error && removal.status === 1 && /Config write rejected:[^\n]+\(size-drop:\d+->\d+\)/.test(removal.stderr)) {
    assert.equal(readFileSync(env.OPENCLAW_CONFIG_PATH, 'utf8'), before, 'Rejected removal changed the config.');
    console.log('Known OpenClaw limitation: size-drop guard blocked config removal; the disabled definition was preserved.');
  } else {
    assert.ok(!removal.error && removal.status === 0, 'Native server removal failed unexpectedly.');
    assert.ok(!JSON.parse(run(['mcp', 'list', '--json'])).pomodoist, 'Native removal left the server configured.');
  }
  assert.equal(JSON.parse(run(['mcp', 'list', '--json'])).unrelated.enabled, false);
  console.log('Native OpenClaw setup, HTTP consent, stored OAuth credentials, probe, revocation, logout and disable passed.');
} finally {
  if (child && child.exitCode === null) {
    if (process.platform !== 'win32') { try { process.kill(-child.pid, 'SIGTERM'); } catch {} }
    else child.kill();
  }
  try {
    if (userId) await request(`/auth/v1/admin/users/${userId}`, { method: 'DELETE', token: config.SERVICE_ROLE_KEY });
  } finally { rmSync(state, { recursive: true, force: true }); }
}
