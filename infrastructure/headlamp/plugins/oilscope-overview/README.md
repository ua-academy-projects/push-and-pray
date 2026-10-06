# OilScope Overview

The Headlamp plugin that renders the post-login landing page for the OilScope
k3s cluster.

Deployment, configuration, permissions and recovery are documented in
[docs/headlamp.md](../../../../docs/headlamp.md). This file covers working on
the plugin itself.

## Layout

| Path | Contents |
| --- | --- |
| `src/index.tsx` | route and sidebar registration |
| `src/OverviewPage.tsx` | the page: bootstrap, configuration, the five sections |
| `src/components/Panel.tsx` | loading, forbidden, unavailable and stale rendering |
| `src/sections/` | one component per section |
| `src/lib/` | the pure logic, and its tests |

Everything that decides whether something is healthy lives in `src/lib` with no
React in it, so it is tested directly with `node:test`.

## Commands

```bash
npm ci        # install the pinned SDK
npm run tsc   # typecheck
npm test      # the logic tests
npm run build # produces dist/main.js
```

`dist/` is not committed. Deployment builds it and publishes it as a ConfigMap.

## The landing page registration

`src/index.tsx` registers the page on `path: '/'` with `useClusterURL: true`,
which resolves to `/c/:cluster/`. Headlamp prepends plugin routes to the default
routes inside a react-router `<Switch>`, so this shadows the built-in cluster
overview, which is where sign-in already lands. There is no redirect, and deep
links are untouched.

Changing that path, or setting `useClusterURL: false`, turns the page back into
an ordinary extra page and the console opens on the default overview again.
[docs/headlamp.md](../../../../docs/headlamp.md#how-the-landing-page-actually-works)
has the full reasoning and the source references.

## Adding a section

1. Put the logic in `src/lib/` as a pure function and test it, including what
   happens when the data is absent or malformed. A section must never present an
   unread value as healthy.
2. Render it in `src/sections/` through `Panel`, which handles the loading,
   forbidden, unavailable and stale states.
3. If it needs a new Kubernetes resource, add the read to the ClusterRole in
   `infrastructure/ansible/oilscope/platform/roles/k3s_headlamp/templates/rbac.yaml.j2`.
   `infrastructure/tests/test_headlamp_rbac.py` enforces the read-only boundary
   and will reject a write verb.
4. If it needs new configuration, add it to the `headlamp.overview` object in
   `infrastructure/terraform/project-config.schema.json`, to the ConfigMap in the
   role, and to `parseOverviewConfig`.

## Version pinning

The SDK version in `package.json` must match `upstream.console.plugin_sdk_version`
in `infrastructure/helm/versions.yml`. CI compares them and fails if they drift.
