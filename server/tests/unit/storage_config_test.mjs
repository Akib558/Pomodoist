import test from 'node:test';
import assert from 'node:assert/strict';

for (const status of [200, 404, 503]) {
  test(`bucket bootstrap handles lookup ${status} without public access`, async () => {
    const previous = globalThis.fetch;
    const calls = [];
    globalThis.fetch = async (url, options) => {
      calls.push({ url, ...options });
      return new Response('{}', { status: calls.length === 1 ? status : 200 });
    };
    try {
      const run = import(`../../scripts/storage-config.mjs?lookup=${status}`);
      if (status === 503) {
        await assert.rejects(run, /lookup failed/);
        assert.equal(calls.length, 1);
      } else {
        await run;
        assert.equal(calls[1].method, status === 200 ? 'PUT' : 'POST');
        assert.deepEqual(JSON.parse(calls[1].body), { id: 'pomodoist-shared', name: 'pomodoist-shared', public: false, file_size_limit: 20000000 });
      }
    } finally { globalThis.fetch = previous; }
  });
}
