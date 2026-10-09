# Headlamp, the operator console

Headlamp is an authenticated Kubernetes console for the AWS k3s cluster. It is
reached at its own hostname, it signs operators in through OIDC, and after
sign-in it opens on **OilScope Overview**, a page this repository owns.

It is off until you configure it. `headlamp.enabled` is `false` in
`project-config.example.json`, nothing in the deployment runs, and no DNS record
or namespace is created.

This guide covers the configuration contract, identity setup, DNS and TLS,
deployment, the permission model, what each panel reads, and recovery.

## Scope

- AWS only, on either Kubernetes platform. The GCP and Azure trees still carry
  the Compose-era design.
- The console shares whatever the application is reached through: the Traefik
  ingress, the `oilscope` ingress class and the `letsencrypt` issuer in both
  modes. With `managed_kubernetes: false` that means the entry node and its
  Elastic IP, so the console inherits the entry-node limitation described in
  [k3s deployment](k3s-deployment.md#one-entry-node-no-load-balancer): if that
  node is lost, the console is unreachable until DNS is repointed. With
  `managed_kubernetes: true` it is reached through the same load balancer as the
  application, so no single node's loss hides it — see
  [Kubernetes modes](kubernetes-modes.md).
- `oidc` mode configures the API server differently per platform: a drop-in
  applied by `configure_k3s_oidc` on k3s, an `aws_eks_identity_provider_config`
  applied by `terraform apply` on EKS. The console's own configuration is
  identical either way.
- The managed PostgreSQL database is not a cluster workload. The page says so
  and links to CloudWatch rather than inventing a pod-shaped health indicator
  for it.

## Pinned versions

`infrastructure/helm/versions.yml` holds the pinned release under
`upstream.console`, verified on 2026-10-04:

| Component | Version |
| --- | --- |
| Headlamp chart | 0.45.0 |
| Headlamp application | 0.45.0 |
| `@kinvolk/headlamp-plugin` | 0.14.0 |

The plugin SDK and the console must move together. CI fails if
`node_modules/@kinvolk/headlamp-plugin` does not match `plugin_sdk_version`, so
bumping one without the other is caught before deployment. `headlamp.chart_version`
in the project configuration overrides the catalogue for a one-off test.

## How the landing page actually works

This was verified against the 0.45.0 sources rather than assumed, because
registering a sidebar page does **not** change where Headlamp opens.

Three facts make it work, and all three are in the pinned release:

1. `frontend/src/components/App/RouteSwitcher.tsx` builds its route list as
   `Object.values(pluginRoutes).concat(defaultRoutes)` and renders it inside a
   react-router `<Switch>`. A `<Switch>` renders the **first** match, and plugin
   routes are prepended, so a plugin route registered on a path that a default
   route already uses shadows that default route.
2. The default route named `cluster` is `path: '/'` with `useClusterURL`
   defaulting to true, which resolves to `/c/:cluster/`. That is the cluster
   overview page.
3. `frontend/src/components/authchooser/index.tsx` sends the user, after a
   successful sign-in, to `location.state.from` and falls back to
   `createRouteURL('cluster')` — again `/c/:cluster/`.

So the plugin registers its page on `path: '/'` with `useClusterURL: true`
(`infrastructure/headlamp/plugins/oilscope-overview/src/index.tsx`). The page then
renders at `/c/main/`, which is exactly where sign-in lands.

Two consequences worth stating:

- **No redirect is involved**, so there is no redirect loop to avoid. The plugin
  does not navigate anywhere; it renders a different component at a path
  Headlamp already sends people to.
- **Deep links keep working.** Opening `/c/main/pods/oilscope/some-pod` while
  signed out redirects to the login route carrying `state.from`, and sign-in
  returns to that exact URL rather than to the overview. The overview is the
  fallback, not an interception.

Opening the bare hostname `/` hits Headlamp's own `chooser` route. Its `Home`
component already pushes to `createRouteURL('cluster', ...)` when it is running
in-cluster with exactly one cluster, which is this deployment, so `/` also ends
on the overview. The default cluster overview is shadowed, not removed, so
`createRouteURL('cluster')` still resolves and nothing else breaks.

## Configuration

Everything lives under a `headlamp` object in the project configuration.
`infrastructure/terraform/project-config.schema.json` is the contract, and it is
the only place configuration is validated — consistent with the rest of this
repository, there are no Terraform or Ansible assertions.

```json
{
  "headlamp": {
    "enabled": false,
    "hostname": "headlamp.example.com",
    "namespace": "headlamp",
    "replicas": 1,
    "session_ttl_seconds": 28800,
    "auth_mode": "token",
    "allowed_cidrs": ["203.0.113.10/32"],
    "overview": {
      "application_url": "https://oilscope.example.com",
      "stale_after_seconds": 120,
      "links": [
        { "label": "CloudWatch dashboard", "url": "https://..." }
      ],
      "components": [
        { "name": "ui", "kind": "Deployment", "label": "UI" },
        { "name": "rabbitmq", "kind": "StatefulSet", "label": "RabbitMQ" }
      ]
    }
  }
}
```

Enabling the console requires `hostname`. `additionalProperties` is closed, so a
typo is an error rather than a silently ignored setting.

`auth_mode` picks how operators prove who they are, and it is the biggest fork
in this guide:

| | `token` (default) | `oidc` |
| --- | --- | --- |
| Who you are to Kubernetes | the `oilscope-viewer` ServiceAccount | your own OIDC identity |
| Signing in | paste the ServiceAccount's token once per browser | redirected to the identity provider |
| Extra configuration | none | an OIDC client, plus the `oidc` block |
| Touches the API servers | no | yes — `configure_k3s_oidc` restarts each in turn |
| Tells operators apart | no, everyone shares one identity | yes, per person in the audit log |

Both run the console's pod with **no cluster permissions of its own**, and both
use the same read-only ClusterRole. `token` is the right choice for a single
operator; move to `oidc` when more than one person needs access, or when you
need to know which of them did what. In `oidc` mode the schema additionally
requires the `oidc` block.

Things the schema cannot check, and you must get right yourself:

- `hostname` must differ from `ingress.hostname` and `kubernetes.api_endpoint`.
  A clash takes the application or the API endpoint down.
- `namespace` must not be `kubernetes.namespace`. The console's runtime identity
  is deliberately separate from the application's.
- `overview.components[].name` is a **suffix**. Deployment prepends
  `name_prefix`, so `"ui"` becomes the `oilscope-ui` Deployment.
- The issuer must be reachable from the browser **and** from every k3s server,
  with a certificate they trust.

Omitting `allowed_cidrs` reuses `kubernetes.admin_allowed_cidrs`, so the console
tracks the same source list as SSH and the Kubernetes API. Setting it to `[]`
accepts every source and leaves OIDC as the only gate.

### Where the client secret lives

Never in the project JSON. `client_secret_secret_id` names a secret container,
exactly as `secret_mappings` does for the application's runtime secrets. At
deployment time Ansible reads the value with the operator's own cloud identity
and writes it straight into a Kubernetes Secret, under `no_log`.

A test in `infrastructure/tests/test_project_config.py` rejects a literal
`client_secret` key in the file, and the schema refuses it too.

The value does not reach Helm. `config.oidc.externalSecret` makes the chart
reference the Secret by name, and the rendered Deployment carries only
`-oidc-client-secret=$(OIDC_CLIENT_SECRET)`. A CI step greps the rendered
manifest to keep it that way. The secret is still visible in the container's
process arguments inside the pod, which is Headlamp's design; anyone who can
read it there can already read the Secret.

## Restricting who can reach the console

Authentication decides who gets in. The allowlist decides who gets to try.

When `allowed_cidrs` is non-empty, deployment creates a Traefik `IPAllowList`
middleware in the console's namespace and attaches it to the Headlamp Ingress
with `traefik.ingress.kubernetes.io/router.middlewares`. Anything from another
address gets **404**, so the hostname does not even admit that a console exists.

Three details make this safe to switch on:

- **ACME still works.** cert-manager's HTTP-01 solver creates its own temporary
  Ingress (`cm-acme-http-solver-…`), which does not carry the annotation, so
  Let's Encrypt reaches the challenge from wherever it likes.
- **The source address is real.** The Cloudflare record is DNS-only
  (`proxied: false`), so Traefik sees the client's own address rather than a
  proxy's. Turning the orange cloud on would make every request appear to come
  from Cloudflare and the allowlist would reject everyone.
- **It cannot lock you out of the cluster.** It guards the console's Ingress
  only. SSH and the Kubernetes API keep their own allowlist, and the operator
  kubeconfig is unaffected.

It *can* lock you out of the console if your address changes, which is the same
failure you already have for SSH, and the fix is the same: update
`admin_allowed_cidrs` (or `headlamp.allowed_cidrs`) and re-run the deployment.
Setting `allowed_cidrs` to `[]` removes the middleware and reverts to OIDC alone.

Traefik v3 renamed this middleware: it is `IPAllowList`, and the v2 spelling
`IPWhiteList` is silently ignored. A test asserts the v3 spelling.

## Signing in with the ServiceAccount token

This is the default and needs no identity provider.

Deployment creates a `oilscope-viewer` ServiceAccount in the console's
namespace, binds it to the read-only ClusterRole, and gives it a
`kubernetes.io/service-account-token` Secret, which does **not** expire. Print
the token:

```bash
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp \
  get secret oilscope-viewer-token -o jsonpath='{.data.token}' | base64 -d
```

Open the console, paste it at the token prompt, and Headlamp keeps it in that
browser's local storage — so this is a once-per-browser step, not once per
session. Every Kubernetes request then carries that token and is authorised as
the ServiceAccount.

Three things worth knowing:

- **The token is a standing credential.** Anyone holding it has the
  ServiceAccount's read-only access from anywhere the allowlist admits. Treat it
  like a password.
- **Revoke by deleting the Secret**, which invalidates the token immediately;
  re-running the deployment issues a new one:

  ```bash
  kubectl -n headlamp delete secret oilscope-viewer-token
  ```

- **For a bounded token instead**, skip the Secret and mint one on demand.
  It stops working on its own, at the cost of reissuing it:

  ```bash
  kubectl -n headlamp create token oilscope-viewer --duration=720h
  ```

Because everyone shares one identity, the audit log cannot tell two operators
apart. That is the trade this mode makes, and it is why `oidc` exists.

## Identity provider setup

Only needed when `auth_mode` is `oidc`. Do this before enabling the console.

1. Create a confidential OIDC client. Note the client ID and secret.
2. Set the redirect URI to exactly:

   ```
   https://<headlamp.hostname>/oidc-callback
   ```

3. Store the client secret in the secret container named by
   `client_secret_secret_id`. Terraform creates the empty container when
   `headlamp.enabled` is true; you put the value in.
4. If the provider emits a groups claim, set `groups_claim` and list
   `allowed_groups`. If it does not, leave `groups_claim` empty and authorise by
   `allowed_users`. The schema rejects `allowed_groups` with no claim to read
   them from, because that combination authorises nobody.

Scopes are **comma separated** — that is what the Headlamp chart expects, not
spaces.

The same `issuer_url` and `client_id` are given to the k3s API server, which is
what makes the browser login mean something to Kubernetes.

### Google as the provider

Google is a full OIDC issuer, so it works for both Headlamp and the k3s API
server with nothing to self-host. It is the simplest option for a single
operator.

1. In the Google Cloud console, **APIs & Services → Credentials → Create
   credentials → OAuth client ID**, type **Web application**.
2. Authorised redirect URI: `https://<headlamp.hostname>/oidc-callback`.
3. On the **OAuth consent screen**, choose *External* and leave the publishing
   status as **Testing**, then add only your own address under **Test users**.
   Google then refuses every other account outright, rather than letting it
   authenticate and fail at the RBAC layer.
4. Put the generated client secret in Secrets Manager:

   ```sh
   aws secretsmanager put-secret-value \
     --secret-id oilscope-headlamp-oidc \
     --secret-string '<the client secret>'
   ```

Two Google-specific consequences:

- **Google ID tokens carry no `groups` claim.** Leave `groups_claim` empty and
  authorise with `allowed_users`. The API server is then configured without a
  groups claim at all.
- **Google ID tokens last one hour.** When one expires Headlamp sends you back
  through sign-in; `session_ttl_seconds` governs Headlamp's own session, not
  Google's token.

The configured client ID must match the token's `aud`, which is what the API
server checks.

## Browser sign-in is not Kubernetes authorisation

Only relevant in `oidc` mode; in `token` mode the pasted token *is* a Kubernetes
credential, so there is nothing to reconcile.

This is the part that is easy to get wrong. Headlamp signing a user in only
proves who they are to Headlamp. With
`config.unsafeUseServiceAccountToken: false` (which this deployment sets, and CI
enforces), Headlamp forwards the user's own ID token to the Kubernetes API. The
API server rejects it unless it has been told to validate that issuer.

`infrastructure/ansible/oilscope/platform/playbooks/configure_k3s_oidc.yml`
writes a drop-in at `/etc/rancher/k3s/config.yaml.d/10-oidc.yaml`:

```yaml
kube-apiserver-arg:
  - "oidc-issuer-url=..."
  - "oidc-client-id=..."
  - "oidc-username-claim=email"
  - "oidc-username-prefix=oidc:"
  - "oidc-groups-claim=groups"
  - "oidc-groups-prefix=oidc:"
```

The playbook runs `serial: 1`: it restarts one server, waits for `/readyz`, waits
for every node to report `Ready`, and only then moves to the next. The prefixes
matter — with `oidc-username-prefix=oidc:` the RBAC subject is
`oidc:alice@example.com`, never a bare name that could collide with a service
account or certificate subject. Deployment applies the prefix when it renders the
bindings, so the two cannot drift.

**Certificate-based access is unaffected.** The operator kubeconfig at
`~/.kube/<name_prefix>-<environment>.yaml` keeps working throughout, which is
the recovery path if OIDC is misconfigured.

## Permissions

Two objects, both rendered from
`roles/k3s_headlamp/templates/rbac.yaml.j2`:

- **ClusterRole `oilscope-operator-read`** — `get`, `list`, `watch` on
  workloads, pods and pod logs, services, endpoints, configmaps, PVCs, PVs,
  namespaces, nodes, events, jobs and cronjobs, ingresses, storage classes,
  cert-manager resources, and node and pod metrics. Plus `create` on the
  self-review APIs (`selfsubjectrulesreviews`, `selfsubjectaccessreviews`,
  `selfsubjectreviews`), which Headlamp calls on every page load to discover
  what the user may do. Those are read-only introspection calls despite the verb.
- **Role `oilscope-operator-overview`** in the application namespace — `get` on
  `services/proxy`, restricted by `resourceNames` to the fetcher service alone.

The role deliberately does **not** grant: `secrets`, `pods/exec`, `pods/attach`,
`pods/portforward`, any write verb on any real resource, any wildcard, or
`cluster-admin`. `infrastructure/tests/test_headlamp_rbac.py` renders the
template and fails the build if any of those appear.

The chart's automatic `cluster-admin` ClusterRoleBinding is disabled
(`clusterRoleBinding.create: false`), so the console's own ServiceAccount has no
cluster permissions at all. Every read is done as the signed-in operator.

Note that `configmaps` read is cluster-wide, which includes `kube-system`.
That is a deliberate trade for a working console; Secrets remain unreadable.

Who those two objects are bound to depends on `auth_mode`:

- **`token`** — the `oilscope-viewer` ServiceAccount, and nothing else.
- **`oidc`** — the configured groups and users, each written with the API
  server's prefix applied, so a single Google user becomes
  `User: oidc:you@example.com`. Deployment applies the prefix, so the binding
  and the API server cannot disagree about the spelling.

In `oidc` mode, with `allowed_groups` and `allowed_users` both empty the
bindings have no subjects, so nobody is authorised and every sign-in ends in a
Kubernetes permission error. The deployment prints this rather than failing.

## DNS and TLS

With `cloudflare.enabled` and `headlamp.enabled` both true, the Cloudflare module
creates a third DNS-only A record for `headlamp.hostname` pointing at the entry
node's Elastic IP, alongside the existing ingress and API records. `proxied` must
stay `false` or the HTTP-01 challenge never reaches the cluster.

The resolved name is published in the `headlamp` Terraform output:

```json
{ "enabled": true, "hostname": "headlamp.example.com", "address": "203.0.113.10", "managed": true }
```

If Cloudflare is disabled, `managed` is `false` and you create the record by
hand: an **A** record for `headlamp.hostname`, pointing at `address`, not
proxied, TTL 60.

The Ingress uses the existing `oilscope` ingress class and the `letsencrypt`
ClusterIssuer, so HTTP-to-HTTPS redirection comes from the shared Traefik
configuration. Deployment waits for the `headlamp-tls` certificate to go Ready
before finishing.

## Deploying

DNS must resolve before the first deploy, or the ACME HTTP-01 challenge fails.

In the default `token` mode there are two steps:

```bash
# 1. The DNS record, once headlamp.enabled and cloudflare.enabled are both true
terraform -chdir=infrastructure/terraform apply

# 2. Platform, application and console
ansible-playbook oilscope.platform.deploy_cluster \
  -e project_config_path="$PWD/project-config.json"
```

`oidc` mode adds two more, between those:

```bash
# 1a. Put the client secret in the container Terraform just created
aws secretsmanager put-secret-value \
  --secret-id oilscope-headlamp-oidc \
  --secret-string '<the OAuth client secret>'

# 1b. Teach the API servers to validate operator tokens, one at a time
ansible-playbook oilscope.platform.configure_k3s_oidc \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path="$PWD/project-config.json"
```

Wait for DNS to resolve before step 2, or the ACME HTTP-01 challenge fails and
the deployment stops waiting for a certificate that cannot be issued.

Step 2 needs Node.js on the operator's machine: it runs `npm ci` (only when
`node_modules` is missing) and `npm run build` in the plugin directory, then
publishes the result. Re-running is idempotent. It reads Terraform's outputs
live, so there is no export to keep in step with the apply.

## How the plugin is delivered

The built bundle is 25 KB, so it ships as a ConfigMap rather than a container
image. No ECR repository, no namespace-scoped pull secret and no credential
renewal are needed.

`oilscope-overview-plugin` in the console's namespace carries three keys, mounted
read-only at `/headlamp/plugins/oilscope-overview`:

| Key | Purpose |
| --- | --- |
| `main.js` | the built bundle |
| `package.json` | name and version; Headlamp skips a plugin folder without one |
| `bootstrap.json` | the namespace and ConfigMap name holding the page's configuration |

A ConfigMap cannot exceed roughly 1 MiB. CI fails the build if the bundle passes
900 KB, with a pointer to switch to image-based delivery before raising it.

`bootstrap.json` is served by Headlamp's static file handler at
`/plugins/oilscope-overview/bootstrap.json`, which is **not** behind
authentication. It therefore carries nothing but a namespace and a ConfigMap
name. The real configuration — including CloudWatch links, which contain the AWS
account ID — lives in the `oilscope-overview` ConfigMap in the application
namespace and is read through the Kubernetes API with the operator's own
permissions. An unauthenticated visitor gets the pointer and nothing else.

The pod is annotated with a SHA-256 of the bundle and of the OIDC secret, so a
changed plugin or a rotated credential rolls the Deployment automatically.

## What each panel reads

Every panel distinguishes loading, forbidden, unavailable and stale from real
data. Nothing renders a healthy state it did not read.

| Panel | Source | When it cannot read |
| --- | --- | --- |
| Environment and links | the `oilscope-overview` ConfigMap | the page says the ConfigMap is forbidden or missing, and names it |
| Application health | Deployments, StatefulSets and Pods in the application namespace | a configured component that is absent is **Not found**, never ready; an unreadable list is forbidden or unavailable |
| Cluster and storage | Nodes, PVCs, and the Metrics API | a node with no `Ready` condition, or one reporting `Unknown`, is shown as `Unknown`; missing metrics say *unavailable* instead of blank |
| Deployed versions and jobs | Pod specs and statuses, Jobs | the requested image reference and the running `imageID` digest are shown separately and compared; a tag-based request shows `n/a` rather than a false match; a job with no status is `unknown`, not succeeded |
| Data collection | the fetcher's `/health`, through the Kubernetes service proxy | a payload without a `status` is rejected; `{"error": "unavailable"}` from the outbox query is shown as unavailable, which is distinct from a pending count of zero |

The fetcher is a ClusterIP service, so the browser cannot reach it. The page
calls
`/api/v1/namespaces/<ns>/services/<fetcher>:http/proxy/health`, which the API
server fetches server-side, authenticated as the operator and authorised by the
`services/proxy` grant. The grant is `get` only on that one named service, so the
fetcher's `POST /v1/fetch` cannot be triggered through it. No new adapter
service, no stored credential and no arbitrary URL proxy are involved.

The field names were read from `services/fetcher/cmd/fetcher/main.go` rather than
assumed: `status`, `provider`, `running`, `queue`, `schedule.next_run`,
`last_result.{scheduled_for,fetched_at,observations,published}`, `last_error`
and `outbox.{pending_count,oldest_pending_seconds}`, with `outbox.error` when the
backlog query itself fails.

A panel older than `stale_after_seconds` is labelled stale rather than presented
as current.

## Updating and rolling back

```bash
# What a change would do
helm --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp diff upgrade headlamp \
  headlamp/headlamp --version 0.45.0 -f infrastructure/helm/values/headlamp.yaml

# History and rollback
helm --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp history headlamp
helm --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp rollback headlamp <revision>
```

The release is installed with `atomic: true`, so a failed upgrade rolls itself
back.

**A Helm rollback does not undo everything.** These are separate, and each needs
its own step:

| Change | Reverted by Helm? | How to revert |
| --- | --- | --- |
| Console Deployment, Service, Ingress | yes | `helm rollback` |
| The plugin ConfigMap | no | it is applied by Ansible; re-run the previous commit's deployment |
| The Cloudflare DNS record | no | `terraform apply` after setting `headlamp.enabled` to false, or delete the record by hand |
| The source allowlist middleware | no | it is applied by Ansible; set `allowed_cidrs` to `[]` and re-run, which deletes it |
| The OIDC client secret container | no | Terraform created it; removing it is a separate `terraform apply`, which deletes it immediately because the module sets no recovery window |
| k3s API server OIDC validation | no | set `auth_mode` back to `token` (or `enabled` to false) and re-run `configure_k3s_oidc`, which removes the drop-in and restarts each server in turn. Never created in `token` mode |
| The `oilscope-viewer` token | no | deleting the Secret revokes it; the next deployment issues a new one |
| Identity provider client and redirect URI | no | change it in the provider |
| RBAC ClusterRole and bindings | no | `kubectl delete clusterrole/clusterrolebinding oilscope-operator-read` |

Rolling the console back does not touch OilScope. The application release, its
hostname and its ingress are independent.

### Rotating the OIDC client secret

Update the value in the secret container, then re-run the deployment. The pod
annotation changes with the secret's hash, so the Deployment rolls
automatically. Nothing else needs restarting.

### Removing Headlamp

```bash
# 1. Only if auth_mode was oidc: stop validating tokens on the API servers,
#    one at a time (set headlamp.enabled to false first)
ansible-playbook oilscope.platform.configure_k3s_oidc ...

# 2. Remove the release and its namespace
helm --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp uninstall headlamp
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml delete namespace headlamp

# 3. Cluster-scoped objects the namespace does not own
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml \
  delete clusterrole,clusterrolebinding oilscope-operator-read

# 4. The ConfigMap left in the application namespace
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml -n <app-namespace> \
  delete configmap oilscope-overview

# 5. The DNS record
terraform -chdir=infrastructure/terraform apply
```

## Troubleshooting

**Reaching the console without DNS or ingress.** This stays available and is the
first thing to try when the hostname is broken:

```bash
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp \
  port-forward svc/headlamp 8080:80
```

Then open `http://localhost:8080`. OIDC will redirect to a callback URI that does
not match `localhost`, so this is useful for confirming the pod serves and the
plugin loaded, not for completing a sign-in.

**The hostname returns 404 from everywhere, including a browser you expect to
work.** That is the source allowlist, not a missing route. Compare your current
address with the configured list:

```bash
curl -s https://api.ipify.org; echo
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp \
  get middleware headlamp-source-allowlist -o jsonpath='{.spec.ipAllowList.sourceRange}'
```

If they differ, update `admin_allowed_cidrs` (or `headlamp.allowed_cidrs`) and
re-run the deployment. Port-forward keeps working regardless.

**The token is rejected, or every panel says forbidden (token mode).** Confirm
the token still exists and that the ServiceAccount is bound:

```bash
kubectl -n headlamp get secret oilscope-viewer-token
kubectl get clusterrolebinding oilscope-operator-read \
  -o jsonpath='{.subjects}'
```

A deleted Secret revokes the token, and re-running the deployment issues a new
one that you must paste again.

**Sign-in succeeds, then every panel says forbidden (oidc mode).** The browser
trusts the token and Kubernetes does not. Check the username the API server
actually sees:

```bash
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml \
  get clusterrolebinding oilscope-operator-read -o yaml
```

and compare its subjects with the claim your provider emits, remembering the
`oidc:` prefix. With Google the usual cause is a mismatch between the email in
`allowed_users` and the account you actually signed in with; with other
providers it is a missing groups claim.

**Sign-in loops back to the login screen.** Headlamp calls
`selfsubjectrulesreviews` before rendering. Kubernetes normally grants this to
everyone through `system:basic-user`; the ClusterRole grants it explicitly as
well, so a loop points at the API server rejecting the token outright. Check
`journalctl -u k3s` on a server for OIDC errors.

**The overview page does not open; the default cluster view does.** The plugin
did not load. Confirm the mount and the plugin list:

```bash
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml -n headlamp \
  exec deploy/headlamp -- ls /headlamp/plugins/oilscope-overview
curl -s https://<headlamp.hostname>/plugins | jq
```

Both `main.js` and `package.json` must be present, or Headlamp skips the folder.

**The data collection panel says forbidden.** The `services/proxy` grant names
the fetcher service explicitly. If `name_prefix` changed, the Role still names
the old service.

**The certificate never goes Ready.** The ACME HTTP-01 challenge needs public
DNS and port 80 reachable — pointing at the entry node on k3s, at the load
balancer on EKS, where `deploy_cluster` publishes that record itself and will
have said so. Check the Order and Challenge objects in the `headlamp` namespace.

## Validation

Run before deploying:

```bash
# Plugin: types, logic, bundle
cd infrastructure/headlamp/plugins/oilscope-overview
npm ci && npm run tsc && npm test && npm run build

# Configuration schema and the RBAC boundary
uv run pytest infrastructure/tests

# Chart rendering
helm template headlamp headlamp \
  --repo https://kubernetes-sigs.github.io/headlamp/ --version 0.45.0 \
  -n headlamp -f infrastructure/helm/values/headlamp.yaml
```

CI runs all of these, plus a check that the rendered manifest contains no
ClusterRoleBinding, no `-unsafe-use-service-account-token`, and no literal client
secret.
