import assert from 'node:assert/strict';
import { test } from 'node:test';
import { OVERVIEW_SIDEBAR_ENTRY, overviewRoute, overviewSidebarEntry } from './registration.ts';

test('the page is registered on the path sign-in already lands on', () => {
  assert.equal(overviewRoute.path, '/');
  assert.equal(
    overviewRoute.useClusterURL,
    true,
    'useClusterURL must stay true: it resolves the route to /c/:cluster/, which is ' +
      "where Headlamp's post-login redirect and single-cluster home both go. " +
      'Setting it false moves the page to /, leaving the default cluster ' +
      'overview as the landing page.'
  );
});

test('the route matches exactly, so it shadows only the cluster overview', () => {
  assert.equal(
    overviewRoute.exact,
    true,
    'a non-exact route on / would swallow every cluster-scoped deep link'
  );
});

test('the route does not opt out of authentication', () => {
  assert.ok(
    !('noAuthRequired' in overviewRoute),
    'the overview reads cluster state and must stay behind authentication'
  );
});

test('the sidebar entry and the route agree, so the entry highlights', () => {
  assert.equal(overviewRoute.sidebar, overviewSidebarEntry.name);
  assert.equal(overviewSidebarEntry.name, OVERVIEW_SIDEBAR_ENTRY);
});

test('the sidebar entry is top level and points at the same path', () => {
  assert.equal(overviewSidebarEntry.parent, null);
  assert.equal(overviewSidebarEntry.url, overviewRoute.path);
  assert.ok(overviewSidebarEntry.label);
});
