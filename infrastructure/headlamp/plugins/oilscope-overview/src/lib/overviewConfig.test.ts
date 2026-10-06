import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  DEFAULT_STALE_AFTER_SECONDS,
  isSafeLink,
  parseConfigMapData,
  parseOverviewConfig,
} from './overviewConfig.ts';

const valid = {
  environment: 'dev',
  clusterName: 'oilscope-dev',
  namespace: 'oilscope',
  applicationUrl: 'https://oilscope.example.com',
  links: [{ label: 'CloudWatch', url: 'https://console.aws.amazon.com/cloudwatch' }],
  components: [
    { name: 'oilscope-ui', kind: 'Deployment', label: 'UI' },
    { name: 'oilscope-rabbitmq', kind: 'StatefulSet' },
  ],
  migrationJobPrefix: 'oilscope-migration',
  registryRefreshCronJob: 'oilscope-registry-refresh',
  fetcherService: { name: 'oilscope-fetcher', port: 'http' },
  staleAfterSeconds: 90,
};

test('a complete configuration parses with every field', () => {
  const config = parseOverviewConfig(valid);

  assert.ok(config);
  assert.equal(config.namespace, 'oilscope');
  assert.equal(config.staleAfterSeconds, 90);
  assert.equal(config.links.length, 1);
  assert.equal(config.components.length, 2);
  assert.equal(config.components[1].label, 'oilscope-rabbitmq');
  assert.deepEqual(config.rejected, []);
});

test('a configuration without a namespace is rejected outright', () => {
  assert.equal(parseOverviewConfig({ ...valid, namespace: '' }), null);
  assert.equal(parseOverviewConfig(null), null);
  assert.equal(parseOverviewConfig([]), null);
});

test('non-https links are dropped and the reason is recorded', () => {
  const config = parseOverviewConfig({
    ...valid,
    links: [
      { label: 'Insecure', url: 'http://internal.example.com' },
      { label: 'Script', url: 'javascript:alert(1)' },
      { label: 'Good', url: 'https://example.com' },
    ],
  });

  assert.equal(config?.links.length, 1);
  assert.equal(config?.links[0].label, 'Good');
  assert.equal(config?.rejected.length, 2);
});

test('a non-https application URL is dropped rather than linked', () => {
  const config = parseOverviewConfig({
    ...valid,
    applicationUrl: 'http://oilscope.example.com',
  });

  assert.equal(config?.applicationUrl, null);
  assert.equal(config?.rejected.length, 1);
});

test('a component with an unsupported kind is dropped', () => {
  const config = parseOverviewConfig({
    ...valid,
    components: [{ name: 'oilscope-metrics', kind: 'CronJob' }, valid.components[0]],
  });

  assert.equal(config?.components.length, 1);
  assert.equal(config?.components[0].name, 'oilscope-ui');
  assert.equal(config?.rejected.length, 1);
});

test('an incomplete fetcher service is dropped so no request is built from it', () => {
  const config = parseOverviewConfig({
    ...valid,
    fetcherService: { name: 'oilscope-fetcher' },
  });

  assert.equal(config?.fetcherService, null);
  assert.equal(config?.rejected.length, 1);
});

test('an absent or invalid stale window falls back to the default', () => {
  assert.equal(
    parseOverviewConfig({ ...valid, staleAfterSeconds: undefined })?.staleAfterSeconds,
    DEFAULT_STALE_AFTER_SECONDS
  );
  assert.equal(
    parseOverviewConfig({ ...valid, staleAfterSeconds: -5 })?.staleAfterSeconds,
    DEFAULT_STALE_AFTER_SECONDS
  );
  assert.equal(
    parseOverviewConfig({ ...valid, staleAfterSeconds: 'soon' })?.staleAfterSeconds,
    DEFAULT_STALE_AFTER_SECONDS
  );
});

test('only https counts as a safe link', () => {
  assert.equal(isSafeLink('https://example.com'), true);
  assert.equal(isSafeLink('http://example.com'), false);
  assert.equal(isSafeLink('javascript:alert(1)'), false);
  assert.equal(isSafeLink('/relative'), false);
  assert.equal(isSafeLink('not a url'), false);
});

test('the ConfigMap key is read and malformed JSON yields no configuration', () => {
  assert.equal(
    parseConfigMapData({ 'overview.json': JSON.stringify(valid) })?.namespace,
    'oilscope'
  );
  assert.equal(parseConfigMapData({ 'overview.json': '{ broken' }), null);
  assert.equal(parseConfigMapData({}), null);
  assert.equal(parseConfigMapData(undefined), null);
});
