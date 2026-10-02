# DNS

Terraform publishes two Cloudflare records, both DNS-only `A` records pointing at
the same address: the Elastic IP of the node named by `kubernetes.entry_node`.
One is the application hostname, the other the Kubernetes API hostname. Applying
the deployment publishes them, and destroying it removes them, so neither hostname
outlives the address it resolves to.

Everything else about the zone — registration, nameservers, mail records,
anything else already living there — stays outside Terraform. The zone is
looked up, never created or destroyed.

## Enable it

```json
{
  "cloudflare": {
    "enabled": true,
    "zone_name": "skynet-zrg.pp.ua",
    "ttl": 60
  }
}
```

The hostnames are **not** configured here. They are read from
`ingress.hostname` — the same value cert-manager requests the certificate for, so
the record and the certificate cannot drift apart — and from
`kubernetes.api_endpoint`. `zone_name` is the apex zone that owns both.

Both hostnames must sit inside `zone_name`, because a record in another zone
cannot be created from this zone's ID. **Nothing enforces that.** The schema
cannot compare one part of the document against another, and there are no
Terraform preconditions in this project. A hostname in the wrong zone reaches
`terraform apply` and fails there, as a Cloudflare API error rather than an
explanatory one.

The API token is read from the environment, never from the project
configuration:

```sh
export CLOUDFLARE_API_TOKEN=...
```

It needs **Zone → DNS → Edit** on that zone, plus the **Zone → Zone → Read**
that the zone lookup performs. With `enabled: false` the provider is never
configured, so a deployment that manages DNS by hand needs no token at all —
including in CI, which runs `terraform validate` and `terraform test` without
one.

## What it publishes

| Setting | Value |
| --- | --- |
| Type | `A`, for both records |
| Names | `ingress.hostname` and `kubernetes.api_endpoint` |
| Content | the Elastic IP of `kubernetes.entry_node` |
| TTL | `cloudflare.ttl`, 60 seconds by default |
| Proxied | always `false` — see below |

`terraform output -json dns` reports both records' identity, hostname, address,
TTL and the entry node they point at, without exposing the token.

### Why one address, and what it costs

There is no load balancer. Both hostnames resolve to one node — the entry node —
which is the cheapest arrangement that works and the least available one.

**Losing the entry node takes down the website and the configured API endpoint,
even though the cluster is healthy.** etcd keeps quorum on the other two nodes,
pods reschedule, workloads keep running, and nobody can reach any of it because
DNS still points at a dead address. There is no automatic failover.

Losing either other node changes nothing externally.

Recovery is manual, and one of:

1. Restore or replace the entry node, keeping its Elastic IP.
2. Repoint both records at another node's Elastic IP — and move Traefik there too,
   if it is pinned to the entry node rather than running as a DaemonSet.

`kubectl` has its own path and needs no DNS change: every node's address is a TLS
SAN on the API server, so `kubectl --server https://<surviving-node>:6443` works
immediately.

Round-robin `A` records across all three nodes were considered and rejected. They
would give failover by client retry, which is not health checking — a node that is
up but not serving still gets handed out — in exchange for a less predictable
failure mode. Health-checked failover needs Cloudflare load balancing, a paid
add-on.

### Why the TTL is short

The address is a reserved AWS Elastic IP, so it survives the stop/start cycle used
to hold costs down. It changes on a destroy-then-apply, which allocates a new one.

More importantly, the TTL is the floor on how fast the manual failover above can
take effect: until caches expire, clients keep dialling the dead node. Sixty
seconds is the shortest value Cloudflare accepts other than `1`, and Cloudflare
does not bill DNS queries on Free or Pro, so it costs nothing. Do **not** raise it
to reduce query volume — it is a recovery-time budget, not a caching tuning knob.
`ttl: 1` means Cloudflare's own "automatic" value, roughly 300 seconds for a
DNS-only record; anything else must be between 60 and 86400.

### Why the record is never proxied

cert-manager obtains the certificate with the ACME **HTTP-01** challenge, which is
answered on port **80** by the solver behind Traefik on the entry node. A proxied
("orange cloud") record makes Cloudflare terminate the connection at its edge and
serve its own response, so the challenge token is never returned from the origin
and both the first issuance and every renewal fail.

Note that this is a different argument from the one that applied under
TLS-ALPN-01, where the objection was that Cloudflare terminates TLS on :443. The
port and the mechanism changed; the conclusion did not. Cloudflare's edge proxies
:80 as well, so HTTP-01 is no more tolerant of the orange cloud than TLS-ALPN-01
was.

**Nothing stops you setting it.** `project-config.schema.json` pins
`cloudflare.proxied` to `false`, but that schema is not applied automatically
anywhere — not by Terraform, not by a pre-commit hook, not in CI. The project
configuration lives outside the repository and is never committed, so no hook
ever sees it. `proxied: true` reaches `terraform apply` intact and breaks
certificate renewal roughly 60 days later, which is far enough from the change
that the cause is not obvious.

The only check is the one you run yourself, before applying:

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
```

Turning the orange cloud on is a real option, but it is a change of ingress
design, not a flag:

- move cert-manager to the **DNS-01** challenge, which needs its own scoped
  Cloudflare token as a Kubernetes Secret, or replace Let's Encrypt with a
  Cloudflare **origin certificate**;
- decide the SSL mode (Full (strict), realistically) so the edge still
  verifies the origin;
- re-check the synthetics canary, which a Cloudflare challenge page would
  correctly fail — see [monitoring](monitoring.md).

A Cloudflare **Tunnel** is the other way to get the same hiding of the origin, and
goes further: `cloudflared` dials out from the cluster, so no inbound 80 or 443 is
needed and the ACME setup becomes unnecessary because Cloudflare terminates TLS.
It would also remove the entry node as a single point of failure, since a tunnel
can run as several replicas. That is a larger change — a `cloudflared` Deployment,
the tunnel token as a Kubernetes Secret, and the public ingress rules removed —
and is not implemented here.

## Verify

```sh
terraform -chdir=infrastructure/terraform output -json dns
dig +short oilscope.skynet-zrg.pp.ua
dig +short api.skynet-zrg.pp.ua
curl -fsS https://oilscope.skynet-zrg.pp.ua/health
kubectl --kubeconfig <path> get nodes
```

Both `dig` calls should return the same single address — the entry node's Elastic
IP — and it should match the output. If either returns a Cloudflare address
(`104.x` / `172.67.x`) the record is proxied, which the configuration does not
produce; check for a leftover manual record in the dashboard. If they return more
than one address, a round-robin record set has been left behind from an earlier
design.

Records created by hand before this existed are not adopted automatically. An `A`
record already occupying either name makes the first apply fail on a conflict;
delete it in the dashboard, or `terraform import` it, before applying. That
includes any records from the previous single-UI-VM deployment.
