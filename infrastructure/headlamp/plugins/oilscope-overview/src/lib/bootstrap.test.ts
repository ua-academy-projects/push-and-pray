import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BOOTSTRAP_URL, loadBootstrap, parseBootstrap } from './bootstrap.ts';

test('a complete pointer parses', () => {
  assert.deepEqual(
    parseBootstrap({
      namespace: 'oilscope',
      configMapName: 'oilscope-overview',
    }),
    {
      namespace: 'oilscope',
      configMapName: 'oilscope-overview',
    }
  );
});

test('an incomplete pointer is rejected rather than half used', () => {
  assert.equal(parseBootstrap({ namespace: 'oilscope' }), null);
  assert.equal(parseBootstrap({ configMapName: 'oilscope-overview' }), null);
  assert.equal(parseBootstrap({ namespace: '  ', configMapName: 'x' }), null);
  assert.equal(parseBootstrap(null), null);
  assert.equal(parseBootstrap([]), null);
  assert.equal(parseBootstrap('oilscope'), null);
});

test('the pointer is read from the plugin asset path', async () => {
  let requested = '';

  const result = await loadBootstrap((async (url: string) => {
    requested = url;

    return {
      ok: true,
      json: async () => ({
        namespace: 'oilscope',
        configMapName: 'oilscope-overview',
      }),
    };
  }) as unknown as typeof fetch);

  assert.equal(requested, BOOTSTRAP_URL);
  assert.equal(result?.namespace, 'oilscope');
});

test('a missing pointer file yields nothing rather than throwing', async () => {
  const result = await loadBootstrap((async () => ({
    ok: false,
  })) as unknown as typeof fetch);

  assert.equal(result, null);
});
