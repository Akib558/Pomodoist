#!/usr/bin/env node
import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';

assert(process.argv.includes('--local'), 'Refusing network mutations without --local');
const env = parseEnv(await readFile(new URL('../.env', import.meta.url), 'utf8'));
const base = new URL(env.SUPABASE_PUBLIC_URL || '');
assert(['localhost', '127.0.0.1', '[::1]'].includes(base.hostname) && base.protocol === 'http:'
  && base.pathname === '/' && !base.username && !base.password && !base.search && !base.hash, 'SUPABASE_PUBLIC_URL must be loopback HTTP');
assert(base.port === '55421', 'This acceptance test only targets the isolated :55421 stack');
assert(env.ANON_KEY && env.SERVICE_ROLE_KEY, 'ANON_KEY and SERVICE_ROLE_KEY are required');
const resource = `${base.origin}/functions/v1/pomodoist-mcp`, protocol = '2025-11-25';
const users = [], clients = [], stamp = `${Date.now()}-${process.pid}`;

const json = value => JSON.stringify(value);
// A cold Deno Edge worker can exceed a short deadline on its first request, so
// retry transport timeouts instead of reporting a false acceptance failure.
async function send(url, init) {
  for (let attempt = 1; ; attempt++) {
    try { return await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) }); }
    catch (error) {
      if (attempt >= 3 || error.name !== 'TimeoutError') throw error;
      await new Promise(resolve => setTimeout(resolve, 1_000 * attempt));
    }
  }
}
async function request(path, { method = 'GET', token, body, form, headers = {}, ok = [200] } = {}) {
  const response = await send(new URL(path, base), { method, headers: {
    ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers,
    ...(body ? { 'Content-Type': 'application/json' } : {}),
    ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
  }, body: body ? json(body) : form ? new URLSearchParams(form) : undefined, redirect: 'manual' });
  const text = await response.text();
  let value = text; try { value = text ? JSON.parse(text) : null; } catch {}
  if (!ok.includes(response.status)) throw new Error(`${method} ${new URL(path, base).pathname}: HTTP ${response.status}`);
  return { status: response.status, headers: response.headers, body: value };
}
const anon = (path, options = {}) => request(path, { ...options, headers: { apikey: env.ANON_KEY, ...options.headers } });
const uuid = value => assert.match(value, /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
const b64 = bytes => Buffer.from(bytes).toString('base64url');
const decodeJwt = token => JSON.parse(Buffer.from(token.split('.')[1], 'base64url'));
function rpcBody(response) {
  if (response.headers.get('content-type')?.includes('text/event-stream')) {
    const data = String(response.body).split('\n').find(line => line.startsWith('data:'))?.slice(5).trim();
    assert(data, 'SSE response has no data event'); return JSON.parse(data);
  }
  return response.body;
}
async function account(label) {
  const credentials = { email: `openclaw-${stamp}-${label}@example.invalid`, password: b64(randomBytes(24)) };
  const signup = await anon('/auth/v1/signup', { method: 'POST', body: credentials });
  uuid(signup.body.user.id); users.push(signup.body.user.id);
  const login = await anon('/auth/v1/token?grant_type=password', { method: 'POST', body: credentials });
  assert(login.body.access_token, 'Password login returned no token'); return login.body.access_token;
}
async function register(label) {
  const redirect = `http://127.0.0.1:${49150 + clients.length}/callback`;
  const response = await request('/auth/v1/oauth/clients/register', { method: 'POST', ok: [201], body: {
    redirect_uris: [redirect], client_name: `openclaw-acceptance-${stamp}-${label}`, client_type: 'public',
    token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'],
  }});
  const client = { id: response.body.client_id, redirect, label }; uuid(client.id);
  assert.equal(response.body.client_type, 'public'); assert.equal(response.body.registration_type, 'dynamic');
  assert.equal(response.body.client_secret, undefined); assert.deepEqual(response.body.redirect_uris, [redirect]);
  clients.push(client); return client;
}
async function authorization(client, accountToken, verifier = b64(randomBytes(40)), intruderToken) {
  const state = b64(randomBytes(18)), challenge = b64(createHash('sha256').update(verifier).digest());
  const query = new URLSearchParams({ client_id: client.id, redirect_uri: client.redirect, response_type: 'code',
    scope: 'email offline_access', state, resource, code_challenge: challenge, code_challenge_method: 'S256' });
  const start = await request(`/auth/v1/oauth/authorize?${query}`, { ok: [302] });
  const consent = new URL(start.headers.get('location')); assert.equal(consent.origin, new URL(env.SITE_URL).origin);
  assert.equal(consent.pathname, '/oauth/consent'); const id = consent.searchParams.get('authorization_id'); assert(id);
  const details = await request(`/auth/v1/oauth/authorizations/${id}`, { token: accountToken });
  let approved = details;
  if (!details.body.redirect_url) {
    assert.equal(details.body.client.id, client.id); assert.equal(details.body.redirect_uri, client.redirect);
    if (intruderToken) await request(`/auth/v1/oauth/authorizations/${id}`, { token: intruderToken, ok: [404] });
    approved = await request(`/auth/v1/oauth/authorizations/${id}/consent`, { method: 'POST', token: accountToken, body: { action: 'approve' } });
  }
  const callback = new URL(approved.body.redirect_url); assert.equal(`${callback.origin}${callback.pathname}`, client.redirect);
  assert.equal(callback.searchParams.get('state'), state); const code = callback.searchParams.get('code'); assert(code);
  return { code, verifier };
}
async function exchange(client, grant, ok = [200]) {
  return request('/auth/v1/oauth/token', { method: 'POST', form: { client_id: client.id, resource, ...grant }, ok });
}
async function connect(client, accountToken) {
  const flow = await authorization(client, accountToken);
  const token = await exchange(client, { grant_type: 'authorization_code', code: flow.code, redirect_uri: client.redirect, code_verifier: flow.verifier });
  assert.equal(token.body.token_type.toLowerCase(), 'bearer'); assert(token.body.access_token && token.body.refresh_token && token.body.expires_in > 0);
  const claims = decodeJwt(token.body.access_token); assert.equal(claims.iss, `${base.origin}/auth/v1`); assert.equal(claims.aud, resource);
  assert.equal(claims.role, 'pomodoist_mcp'); assert.equal(claims.client_id, client.id); uuid(claims.sub); uuid(claims.session_id);
  return { access: token.body.access_token, refresh: token.body.refresh_token, claims, code: flow.code, verifier: flow.verifier };
}
async function mcp(token, method, params, id = randomUUID(), ok = [200]) {
  const response = await request('/functions/v1/pomodoist-mcp', { method: 'POST', token, ok, headers: {
    Accept: 'application/json, text/event-stream', 'Content-Type': 'application/json', ...(method === 'initialize' ? {} : { 'mcp-protocol-version': protocol }),
  }, body: { jsonrpc: '2.0', id, method, params } });
  return rpcBody(response);
}
async function tool(token, name, args) {
  const value = await mcp(token, 'tools/call', { name, arguments: args });
  assert.equal(value.result?.structuredContent?.ok, true, `${name} failed: ${value.result?.structuredContent?.error?.code || 'unknown'}`);
  return value.result.structuredContent.data;
}
async function cleanup() {
  // Account deletion also removes its OAuth grants and synchronized fixture data.
  const results = await Promise.allSettled(users.map(id => request(`/auth/v1/admin/users/${id}`, {
    method: 'DELETE', token: env.SERVICE_ROLE_KEY, headers: { apikey: env.SERVICE_ROLE_KEY }, ok: [200, 204, 404],
  })));
  const failures = results.filter(result => result.status === 'rejected').map(result => result.reason);
  if (failures.length) throw new AggregateError(failures, 'Synthetic account cleanup failed; dispose of the local test stack.');
}

let primary;
let failure;
try {
  const authMeta = (await request('/.well-known/oauth-authorization-server/auth/v1')).body;
  assert.equal(authMeta.issuer, `${base.origin}/auth/v1`); assert(authMeta.code_challenge_methods_supported.includes('S256'));
  assert(authMeta.grant_types_supported.includes('authorization_code') && authMeta.grant_types_supported.includes('refresh_token'));
  assert(authMeta.registration_endpoint); const protectedMeta = (await request('/.well-known/oauth-protected-resource/functions/v1/pomodoist-mcp')).body;
  assert.equal(protectedMeta.resource, resource); assert.deepEqual(protectedMeta.authorization_servers, [`${base.origin}/auth/v1`]);
  primary = await account('owner'); const intruder = await account('intruder');
  const a = await register('a'), b = await register('b'); assert.notEqual(a.id, b.id);
  const stolen = await authorization(a, primary, b64(randomBytes(40)), intruder);
  await exchange(a, { grant_type: 'authorization_code', code: stolen.code, redirect_uri: a.redirect, code_verifier: 'x'.repeat(43) }, [400]);
  const A = await connect(a, primary), B = await connect(b, primary);
  assert.notEqual(A.claims.session_id, B.claims.session_id); assert.notEqual(A.claims.sub, B.claims.sub);
  await exchange(a, { grant_type: 'authorization_code', code: A.code, redirect_uri: a.redirect, code_verifier: A.verifier }, [400]);
  await mcp('', 'initialize', {}, randomUUID(), [401]); await mcp(primary, 'initialize', {}, randomUUID(), [401]);
  for (const [client, token] of [[a, A.access], [b, B.access]]) {
    const init = await mcp(token, 'initialize', { protocolVersion: protocol, capabilities: {}, clientInfo: { name: client.label, version: '1' } });
    assert.equal(init.result.protocolVersion, protocol); const list = await mcp(token, 'tools/list', {});
    assert(list.result.tools.some(tool => tool.name === 'openclaw_create_task'));
  }
  const requestId = randomUUID(), content = `OpenClaw acceptance ${stamp}`;
  const created = await tool(A.access, 'openclaw_create_task', { request_id: requestId, arguments: { content } }); uuid(created.id);
  const replay = await tool(A.access, 'openclaw_create_task', { request_id: requestId, arguments: { content } }); assert.equal(replay.id, created.id);
  const changed = await mcp(A.access, 'tools/call', { name: 'openclaw_create_task', arguments: { request_id: requestId, arguments: { content: `${content} changed` } } });
  assert.equal(changed.result.structuredContent.ok, false); assert.equal(changed.result.structuredContent.error.code, 'invalid_argument');
  assert.equal((await tool(B.access, 'openclaw_get_task', { task_id: created.id })).content, content);
  const pullArgs = { p_app_id: 'pomodoist', p_device_id: `openclaw-${stamp}`, p_since_revision: 0, p_limit: 500 };
  const pulled = await anon('/rest/v1/rpc/pull_changes', { method: 'POST', token: primary, body: pullArgs });
  const taskChange = pulled.body.changes.find(change => change.entityId === created.id); assert(taskChange);
  const now = new Date().toISOString(), directContent = `${content} direct`;
  const pushed = await anon('/rest/v1/rpc/push_changes', { method: 'POST', token: primary, body: { p_app_id: 'pomodoist', p_device_id: `direct-${stamp}`, p_operations: [{
    opId: randomUUID(), entityType: 'task', entityId: created.id, operation: 'upsert', clientUpdatedAt: now,
    payload: { ...taskChange.data, content: directContent, title: directContent, updatedAt: now },
  }] }}); assert.equal(pushed.body.applied.length, 1);
  assert.equal((await tool(A.access, 'openclaw_get_task', { task_id: created.id })).content, directContent);
  await tool(A.access, 'openclaw_update_task', { request_id: randomUUID(), arguments: { task_id: created.id, priority: 2, schedule: { type: 'all_day', date: '2026-09-10' } } });
  await tool(B.access, 'openclaw_set_task_details', { request_id: randomUUID(), arguments: { task_id: created.id, deadline_date: '2026-09-11', duration_seconds: 900 } });
  const scheduled = await tool(A.access, 'openclaw_get_task', { task_id: created.id });
  assert.equal(scheduled.priority, 2);
  assert.equal(JSON.parse(scheduled.dueJson).date.slice(0, 10), '2026-09-10');
  assert.equal(JSON.parse(scheduled.deadlineJson).date.slice(0, 10), '2026-09-11');
  assert.equal(scheduled.durationSeconds, 900);
  let focus = await tool(A.access, 'openclaw_focus', { request_id: randomUUID(), arguments: { action: 'start', task_id: created.id } });
  let current = await tool(B.access, 'openclaw_get_focus', {}); assert.equal(current.focus.run.id, focus.id);
  assert.equal(current.focus.interval.plannedSeconds, 1500);
  assert.equal(current.focus.interval.status, 'running');
  const ids = { run_id: current.focus.run.id, interval_id: current.focus.interval.id };
  const stale = await mcp(B.access, 'tools/call', { name: 'openclaw_focus', arguments: { request_id: randomUUID(), arguments: { action: 'pause', run_id: randomUUID(), interval_id: randomUUID() } } });
  assert.equal(stale.result.structuredContent.error.code, 'conflict');
  await tool(B.access, 'openclaw_focus', { request_id: randomUUID(), arguments: { action: 'pause', ...ids } });
  current = await tool(A.access, 'openclaw_get_focus', {}); const resumedIds = { run_id: current.focus.run.id, interval_id: current.focus.interval.id };
  assert.equal(current.focus.interval.status, 'paused');
  await tool(A.access, 'openclaw_focus', { request_id: randomUUID(), arguments: { action: 'resume', ...resumedIds } });
  current = await tool(B.access, 'openclaw_get_focus', {});
  assert.equal(current.focus.interval.status, 'running');
  await tool(B.access, 'openclaw_focus', { request_id: randomUUID(), arguments: { action: 'stop', run_id: current.focus.run.id, interval_id: current.focus.interval.id, confirmed: true } });
  assert.equal((await tool(A.access, 'openclaw_get_focus', {})).focus, null);
  await tool(A.access, 'openclaw_complete_task', { request_id: randomUUID(), arguments: { task_id: created.id } });
  assert.equal((await tool(B.access, 'openclaw_get_task', { task_id: created.id })).status, 'completed');
  const refreshed = await exchange(a, { grant_type: 'refresh_token', refresh_token: A.refresh }); assert(refreshed.body.refresh_token);
  await exchange(b, { grant_type: 'refresh_token', refresh_token: refreshed.body.refresh_token }, [400]);
  let grants = await anon('/auth/v1/user/oauth/grants', { token: primary }); assert([a.id, b.id].every(id => grants.body.some(g => g.client.id === id)));
  await anon(`/auth/v1/user/oauth/grants?client_id=${a.id}`, { method: 'DELETE', token: primary, ok: [204] });
  await mcp(refreshed.body.access_token, 'initialize', { protocolVersion: protocol, capabilities: {}, clientInfo: { name: 'revoked', version: '1' } }, randomUUID(), [401]);
  await mcp(refreshed.body.access_token, 'tools/call', { name: 'openclaw_create_task',
    arguments: { request_id: requestId, arguments: { content } } }, randomUUID(), [401]);
  await exchange(a, { grant_type: 'refresh_token', refresh_token: refreshed.body.refresh_token }, [400]);
  assert((await tool(B.access, 'openclaw_get_task', { task_id: created.id })).id === created.id);
  await exchange(b, { grant_type: 'refresh_token', refresh_token: B.refresh });
  grants = await anon('/auth/v1/user/oauth/grants', { token: primary }); assert(!grants.body.some(g => g.client.id === a.id) && grants.body.some(g => g.client.id === b.id));
} catch (error) { failure = error; throw error; }
finally {
  try { await cleanup(); }
  catch (error) { if (failure) console.error(error); else throw error; }
}
console.log('OpenClaw HTTP acceptance passed: OAuth DCR/PKCE, MCP tools, sync, idempotency, Focus, refresh, and revocation.');
