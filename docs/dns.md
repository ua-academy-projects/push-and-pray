# DNS

Terraform publishes one Cloudflare record: an `A` record for the UI's public
hostname, pointing at the UI VM's public address. Applying the deployment
publishes it, and destroying the deployment removes it, so the hostname never
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

The hostname is **not** configured here. It is read from the UI VM's
`vms.<ui>.public_endpoint.hostname`, which is the same value Traefik requests
its certificate for — so the record and the certificate cannot drift apart.
`zone_name` is the apex zone that owns it; Terraform rejects a hostname that
sits outside the zone, because a record in another zone cannot be created from
this zone's ID.

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
| Type | `A` |
| Name | the UI VM's `public_endpoint.hostname` |
| Content | the UI VM's public IP in the configuration's `default_cloud` |
| TTL | `cloudflare.ttl`, 60 seconds by default |
| Proxied | always `false` — see below |

`terraform output -json dns` reports the record's identity, hostname, address
and TTL without exposing the token.

### Why one address

DNS publishes a single address, so it has to name a single VM: the UI in
`default_cloud`. A UI VM pinned to the other cloud with its own `cloud`
override keeps serving on its own IP, but the hostname does not resolve to it.
Round-robin across both clouds is deliberately not done — without health
checking it would keep sending half the traffic to a cloud that is down, and
health-checked failover needs Cloudflare load balancing, which is a paid
add-on.

### Why the TTL is short

The address is a reserved AWS Elastic IP / GCP static address, so it survives
the stop/start cycle used to hold costs down. It does change on a
destroy-then-apply, which allocates a new one. 60 seconds bounds how long
resolvers keep answering with the previous, now-dead address; Cloudflare does
not bill DNS queries on Free or Pro, so the short TTL costs nothing. Raise it
once the environment stops being rebuilt. `ttl: 1` means Cloudflare's own
"automatic" value, roughly 300 seconds for a DNS-only record; anything else
must be between 60 and 86400.

### Why the record is never proxied

Traefik obtains its certificate with the ACME **TLS-ALPN-01** challenge, which
is answered on port 443 by the origin itself. A proxied ("orange cloud")
record makes Cloudflare terminate TLS at its edge, so the challenge never
arrives and both the first issuance and every renewal fail. Terraform
therefore refuses `proxied: true` with an explanatory error rather than
letting a one-word config change silently break certificate renewal 60 days
later.

Turning the orange cloud on is a real option, but it is a change of ingress
design, not a flag:

- move Traefik to the **DNS-01** challenge, which needs its own scoped
  Cloudflare token deployed to the UI VM, or replace Let's Encrypt with a
  Cloudflare **origin certificate**;
- decide the SSL mode (Full (strict), realistically) so the edge still
  verifies the origin;
- re-check the synthetics canary, which a Cloudflare challenge page would
  correctly fail — see [monitoring](monitoring.md).

A Cloudflare **Tunnel** is the other way to get the same hiding of the origin,
and goes further: `cloudflared` dials out from the UI VM, so the VM needs no
public IP and no inbound 443 at all, and Traefik's ACME setup becomes
unnecessary because Cloudflare terminates TLS. That is a larger change —
a `cloudflared` role, the tunnel token as a managed secret, and the UI's public
IP and security-group rules removed — and is not implemented here.

## Verify

```sh
terraform -chdir=infrastructure/terraform output -json dns
dig +short oilscope.skynet-zrg.pp.ua
curl -fsS https://oilscope.skynet-zrg.pp.ua/health
```

`dig` should return the address from the output. If it returns a Cloudflare
address (`104.x` / `172.67.x`) the record is proxied, which the configuration
does not produce — check for a leftover manual record in the dashboard.

Records created by hand before this existed are not adopted automatically. An
`A` record already occupying the same name makes the first apply fail on a
conflict; delete it in the dashboard, or `terraform import` it, before
applying.
