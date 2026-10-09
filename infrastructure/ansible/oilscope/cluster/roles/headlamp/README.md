# Headlamp

Runs [Headlamp](https://headlamp.dev), the Kubernetes web UI, reachable only
from the tailnet, by name, over plain HTTP.

## What it creates

| Resource | Purpose |
| --- | --- |
| Helm release `headlamp` in `headlamp` | The UI; `Service/headlamp` on port 80, `ClusterIP` |
| `ServiceAccount`, `ClusterRole`, `ClusterRoleBinding` `headlamp-viewer` | The account people sign in as: read everything, change nothing |
| `Middleware/tailnet-only` | Traefik's `ipAllowList`: anything outside `tailscale.address_range` gets 403 |
| `Ingress/headlamp` | `headlamp.hostname` → `Service/headlamp`, through that Middleware |

## Rights

The chart binds Headlamp's own service account to `cluster-admin` by default.
`files/values.yaml` turns that off: Headlamp acts with the token the person
signs in with, so the pod needs no rights in the cluster, and has none.

The account to sign in with, `headlamp-viewer`, may `get`, `list` and
`watch` every resource of every API group - Secrets and custom resources
(`Cluster`, `Certificate`, `Middleware`...) included - and nothing else. The
built-in `view` role would not do: it leaves Secrets out on purpose.

Checked with `kubectl auth can-i`: the viewer lists Secrets, CloudNativePG
clusters, certificates and nodes, and may not delete pods, create
deployments or update Secrets; Headlamp's own account may not list Secrets.

A token to sign in with, valid for a day:

```bash
kubectl create token headlamp-viewer -n headlamp --duration=24h
```

## Only from the tailnet

An internal name is no protection by itself: Traefik routes by the `Host`
header, and anyone can send it to the public address. The `ipAllowList`
Middleware is the protection, and it works only because Traefik sees the
real client address - see the `traefik` role. Tested: through the tailnet
200, from the internet with the same `Host` header 403.

## Why HTTP

The name is not in public DNS, so Let's Encrypt cannot check it over
HTTP-01. The traffic already travels encrypted inside the tailnet's
WireGuard tunnel up to the bastion; from there to the node it crosses the
cloud's private network. The browser still labels the page "not secure".

## Opening it

The browser's machine must be in the tailnet, accept the bastions' routes,
and resolve the name - a hosts file entry pointing at the internal address of
a node with a public address (ports 80/443 are open only there):

```
10.0.1.4  headlamp.oilscope.internal
```

## License

GPL-2.0-or-later
