import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const endpoint = 'https://tasks.example.com/functions/v1/pomodoist-mcp';
const configure = fileURLToPath(new URL('./configure.mjs', import.meta.url));

// The external CLI is the boundary: exercise our real executable and its writes.
function setup(t, { servers = {}, unsupported = false, failure = '', invalid = false } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'pomodoist-setup-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const config = join(directory, 'servers.json');
  const log = join(directory, 'calls.jsonl');
  writeFileSync(config, JSON.stringify(servers));
  writeFileSync(log, '');
  writeFileSync(join(directory, 'openclaw'), `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify(args) + '\\n');
if (args.join(' ') === 'mcp --help') {
  console.log(${JSON.stringify(unsupported ? '  list\n  set\n  unset' : '  list\n  set\n  login\n  doctor\n  logout\n  unset')});
} else if (args.join(' ') === 'mcp doctor --help') {
  console.log('  --probe  Connect and discover tools');
} else if (args[1] === ${JSON.stringify(failure)}) {
  process.exit(1);
} else if (args.join(' ') === 'mcp list --json') {
  console.log(${invalid ? "'not JSON: secret-value'" : `fs.readFileSync(${JSON.stringify(config)}, 'utf8')`});
} else if (args[1] === 'set') {
  const value = JSON.parse(fs.readFileSync(${JSON.stringify(config)}, 'utf8'));
  value[args[2]] = JSON.parse(args[3]);
  fs.writeFileSync(${JSON.stringify(config)}, JSON.stringify(value));
}
`, { mode: 0o700 });
  return {
    directory,
    run: (args, script = configure) => spawnSync(process.execPath, [script, ...args], {
      env: { ...process.env, PATH: `${directory}:${process.env.PATH}` }, encoding: 'utf8',
    }),
    config: () => JSON.parse(readFileSync(config, 'utf8')),
    calls: () => readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse),
  };
}

test('preview never invokes OpenClaw or changes configuration', t => {
  const fixture = setup(t, { unsupported: true });
  const result = fixture.run([endpoint]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).mcp.servers.pomodoist.url, endpoint);
  assert.deepEqual(fixture.calls(), []);
  assert.deepEqual(fixture.config(), {});
});

test('unsupported CLI fails before writing or launching OAuth', t => {
  const fixture = setup(t, { unsupported: true });
  const result = fixture.run([endpoint, '--apply']);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /2026\.9\.3/);
  assert.deepEqual(fixture.config(), {});
  assert.ok(!fixture.calls().some(args => ['set', 'login'].includes(args[1])));
});

test('another endpoint or stdio server cannot be overwritten', t => {
  for (const existing of [{ url: 'https://other.example.com/mcp' }, { command: 'local-mcp' }]) {
    const fixture = setup(t, { servers: { pomodoist: existing } });
    const result = fixture.run([endpoint, '--apply']);
    assert.equal(result.status, 1);
    assert.deepEqual(fixture.config(), { pomodoist: existing });
    assert.ok(!fixture.calls().some(args => ['set', 'login'].includes(args[1])));
  }
});

test('unreadable registry fails closed without echoing its contents', t => {
  for (const options of [{ invalid: true }, { failure: 'list' }]) {
    const fixture = setup(t, options);
    const result = fixture.run([endpoint, '--apply']);
    assert.equal(result.status, 1);
    assert.doesNotMatch(result.stdout + result.stderr, /secret-value/);
    assert.deepEqual(fixture.config(), {});
  }
});

test('same endpoint can enable writes without changing another server', t => {
  const unrelated = { command: 'another-mcp', args: ['--safe'] };
  const fixture = setup(t, { servers: { pomodoist: { url: endpoint }, unrelated } });
  const result = fixture.run([endpoint, '--write', '--apply']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(fixture.config().unrelated, unrelated);
  assert.ok(fixture.config().pomodoist.toolFilter.include.includes('openclaw_create_task'));
  assert.deepEqual(fixture.calls().slice(-3).map(args => args[1]), ['set', 'login', 'doctor']);
});

test('failed setup steps stop without claiming connection or retrying', t => {
  for (const failure of ['set', 'login', 'doctor']) {
    const fixture = setup(t, { failure });
    const result = fixture.run([endpoint, '--apply']);
    assert.equal(result.status, 1);
    assert.doesNotMatch(result.stdout, /Connected\./);
    const calls = fixture.calls().filter(args => !args.includes('--help'));
    assert.equal(calls.at(-1)[1], failure);
    assert.equal(calls.filter(args => args[1] === failure).length, 1);
  }
});

test('published skill folder runs independently of the repository', t => {
  const fixture = setup(t);
  const skill = join(fixture.directory, 'skills', 'pomodoist');
  cpSync(new URL('./skills/pomodoist', import.meta.url), skill, { recursive: true });
  const result = fixture.run([endpoint, '--apply'], join(skill, 'scripts', 'configure.mjs'));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fixture.config().pomodoist.url, endpoint);
});
