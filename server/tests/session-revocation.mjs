#!/usr/bin/env node
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';

assert(process.argv.includes('--local'), 'This test creates accounts; pass --local to target a disposable local stack');
const env = parseEnv(await readFile(new URL('../.env', import.meta.url), 'utf8'));
const base = new URL(process.env.POMODOIST_SESSION_TEST_API_URL || env.SUPABASE_PUBLIC_URL);
assert(base.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)
  && base.pathname === '/' && !base.username && !base.password && !base.search && !base.hash,
  'Session tests only accept loopback HTTP');
assert(env.ANON_KEY && env.SERVICE_ROLE_KEY, 'Local API credentials are required');

async function request(path, { method = 'GET', token = env.ANON_KEY, body, schema, status = 200 } = {}) {
  const response = await fetch(new URL(path, base), {
    method, redirect: 'error', signal: AbortSignal.timeout(15_000),
    headers: {
      apikey: env.ANON_KEY, Authorization: `Bearer ${token}`,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(schema ? { 'Accept-Profile': schema, 'Content-Profile': schema } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  assert.equal(response.status, status, `${method} ${path} must return HTTP ${status}`);
  return response.status === 204 ? null : response.json();
}

const password = randomBytes(24).toString('base64url');
const email = `session-revocation-${randomUUID()}@example.invalid`;
const credentials = { email, password };
const user = await request('/auth/v1/admin/users', {
  method: 'POST', token: env.SERVICE_ROLE_KEY, body: { ...credentials, email_confirm: true },
});
try {
  const login = () => request('/auth/v1/token?grant_type=password', { method: 'POST', body: credentials });
  const a = await login(), b = await login();
  const claims = token => JSON.parse(Buffer.from(token.split('.')[1], 'base64url'));
  assert.notEqual(claims(a.access_token).session_id, claims(b.access_token).session_id);
  const profile = `/rest/v1/profiles?id=eq.${user.id}&select=id,display_name`;
  const pull = { p_app_id: 'pomodoist', p_device_id: 'session-test', p_since_revision: 0 };
  const push = { p_app_id: 'pomodoist', p_device_id: 'session-test', p_operations: [{
    opId: randomUUID(), entityType: 'task', entityId: randomUUID(),
    operation: 'upsert', payload: { title: 'Session revocation fixture' },
  }] };
  assert.equal((await request(profile, { token: b.access_token }))[0].id, user.id);
  await request(profile, { method: 'PATCH', token: b.access_token, body: { display_name: 'Before password change' }, status: 204 });
  for (const schema of ['public', 'api_v1']) {
    await request('/rest/v1/rpc/push_changes', { method: 'POST', token: b.access_token, schema, body: push });
    await request('/rest/v1/rpc/pull_changes', { method: 'POST', token: b.access_token, schema, body: pull });
  }

  const newPassword = randomBytes(24).toString('base64url');
  await request('/auth/v1/user', { method: 'PUT', token: a.access_token, body: { password: newPassword } });
  assert(claims(b.access_token).exp > Date.now() / 1000, 'Revoked JWT must still be unexpired');
  const denied = { token: b.access_token, status: 401 };
  assert.equal((await request(profile, denied)).code, 'PT401');
  assert.equal((await request(profile, { ...denied, method: 'PATCH', body: { display_name: 'Revoked write' } })).code, 'PT401');
  for (const schema of ['public', 'api_v1']) {
    for (const [rpc, body] of [['pull_changes', pull], ['push_changes', push], ['get_account_overview', {}]]) {
      assert.equal((await request(`/rest/v1/rpc/${rpc}`, { ...denied, method: 'POST', schema, body })).code, 'PT401');
    }
  }
  await request('/auth/v1/token?grant_type=refresh_token', {
    method: 'POST', body: { refresh_token: b.refresh_token }, status: 400,
  });
  await request('/auth/v1/token?grant_type=password', { method: 'POST', body: credentials, status: 400 });
  assert.equal((await request(profile, { token: a.access_token }))[0].display_name, 'Before password change');
  assert.equal((await request(profile, { token: env.SERVICE_ROLE_KEY }))[0].id, user.id);
  assert.equal((await request('/rest/v1/rpc/pull_changes', { method: 'POST', body: pull, status: 401 })).code, '42501');
  await request('/rest/v1/rpc/pull_changes', { method: 'POST', token: a.access_token, body: pull });
  const fresh = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password: newPassword } });
  await request(profile, { token: fresh.access_token });

  await request('/auth/v1/logout?scope=local', { method: 'POST', token: fresh.access_token, status: 204 });
  assert.equal((await request(profile, { token: fresh.access_token, status: 401 })).code, 'PT401');
  await request('/rest/v1/rpc/pull_changes', { method: 'POST', token: a.access_token, body: pull });
  console.log('Password change blocks revoked JWT reads/writes in public and api_v1; current/new sessions and local sign-out pass.');
} finally {
  await request(`/auth/v1/admin/users/${user.id}`, { method: 'DELETE', token: env.SERVICE_ROLE_KEY });
}
