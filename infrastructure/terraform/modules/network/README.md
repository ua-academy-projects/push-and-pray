# Network module

Creates the VPC that everything else in the project runs in: one custom-mode
network, a public subnet for the bastion, a private subnet for the application
and database instances, explicit routing, Cloud NAT for outbound-only internet
access, and a least-privilege firewall set.

## What it creates

| Resource | Name | Purpose |
| --- | --- | --- |
| `google_compute_network` | `<prefix>-vpc` | Custom-mode VPC, no auto subnets |
| `google_compute_subnetwork` | `<prefix>-subnet-public` | Bastion and the public-facing UI instance |
| `google_compute_subnetwork` | `<prefix>-subnet-private` | App + database, no external IPs |
| `google_compute_route` | `<prefix>-rt-default-internet` | Explicit `0.0.0.0/0` default route |
| `google_compute_router` / `_router_nat` | `<prefix>-router` / `<prefix>-nat` | Egress-only internet for the private subnet |
| `google_compute_firewall` | see below | Ingress and (optional) egress rules |

Instances are selected by network tag, exported through the `network_tags`
output: `<prefix>-bastion`, `<prefix>-app`, `<prefix>-db`, `<prefix>-ui`. An
instance that carries no tag is reachable by nothing.

The tags are a contract, not a dependency: this module creates the rules, and
whoever creates an instance decides which tag it carries. In particular the UI
instance does not exist yet (issue #14) - the `<prefix>-ui` rule is already in
place and starts applying the moment that instance is tagged.

```bash
terraform output network_tags     # -> { app, bastion, db, ui }
terraform output ui_public_ports  # -> ["80", "443"]
```

## Firewall rules

Ingress (always created):

| Rule | Source | Target | Ports |
| --- | --- | --- | --- |
| `<prefix>-allow-ssh-to-bastion` | `bastion_allowed_cidrs` | `<prefix>-bastion` | `ssh_port` |
| `<prefix>-allow-ssh-from-bastion` | tag `<prefix>-bastion` | `<prefix>-app`, `<prefix>-db`, `<prefix>-ui` | `ssh_port` |
| `<prefix>-allow-app-internal` | VPC subnets only | `<prefix>-app` | `app_ports` |
| `<prefix>-allow-db-from-app` | tag `<prefix>-app` | `<prefix>-db` | `db_port` |
| `<prefix>-allow-ui-public` | `ui_source_ranges` (`0.0.0.0/0`) | `<prefix>-ui` | `ui_public_ports` (`80`, `443`) |
| `<prefix>-allow-internal-icmp` | VPC subnets only | all tags | ICMP |
| `<prefix>-deny-all-ingress` (priority 65533) | `0.0.0.0/0` | everything | all |

Consequences that are deliberate, not accidental:

- The database port has **no** public source range at all. Only instances tagged
  `<prefix>-app` can open it - not even the bastion.
- Application ports are reachable from inside the VPC only. The single
  intentionally public service is the UI, on `80`/`443` and on nothing else: a
  `lifecycle.precondition` fails the plan if `ui_public_ports` ever overlaps
  `app_ports` or `db_port`. A UI that needs to serve an application port gets a
  reverse proxy in front of it, not a wider rule.
- The UI rule is opt-out (`enable_ui_public_ingress = false`) and can be narrowed
  to specific sources with `ui_source_ranges` while the UI is not meant to be
  public yet.
- Port 22 is never opened. SSH lives on `ssh_port` (default `18832`).
- `bastion_allowed_cidrs` rejects `0.0.0.0/0`, `::/0` and any prefix shorter than
  `/8`, in variable validation and again in a `lifecycle.precondition` on the rule.

Egress is permissive by default (GCP's implied allow). Setting
`restrict_egress = true` replaces it with a deny-all at priority 65534 plus narrow
allows: in-VPC traffic, the metadata server, DNS/NTP, and `egress_allowed_ports`
(default `443`). Roll that out in a non-production project first - it breaks
anything talking to an unexpected endpoint.

## Usage

```hcl
module "network" {
  source = "./modules/network"

  project_id  = var.project_id
  region      = var.region
  name_prefix = "oil"

  ssh_port              = 18832
  bastion_allowed_cidrs = ["203.0.113.10/32"]
}
```

Key inputs: `public_subnet_cidr`, `private_subnet_cidr`, `ssh_port`,
`bastion_allowed_cidrs` (required), `app_ports`, `db_port`,
`enable_ui_public_ingress`, `ui_public_ports`, `ui_source_ranges`, `enable_nat`,
`nat_static_ip_count`, `restrict_egress`, `enable_firewall_logging`.
Run `terraform-docs` or read [variables.tf](variables.tf) for the full list.

Key outputs: `network_id`, `public_subnet`, `private_subnet`, `network_tags`,
`nat_name`, `nat_egress_ips`, `firewall_rules`, `egress_firewall_rules`,
`ssh_port`, `db_port`, `ui_public_ports`.

## Access procedure

This module grants no access by itself: it only decides which paths exist. Two
things have to happen for a person to get in.

1. **Add the person's source address.** Append the office or VPN egress address
   (a `/32` where possible) to `bastion_allowed_cidrs` in `terraform.tfvars`,
   open a PR, and apply after review. Requests for `0.0.0.0/0` fail at plan time
   by design.
2. **Add the person's public key** to `ssh_users` of the
   [bastion module](../bastion/README.md), which is where SSH identities live.

The resulting path is fixed:

```
operator -> (ssh_port, allowed CIDR only) -> bastion -> (ssh_port, source tag) -> private instance
private instance -> Cloud NAT -> internet   # outbound only, no inbound path
```

To revoke network access, remove the CIDR and apply. Existing sessions are not
terminated by a firewall change, so also remove the person's key from `ssh_users`.

## Verifying the network

Run after `terraform apply`. Replace `oil` with your `name_prefix`.

```bash
gcloud compute networks describe oil-vpc --format='value(name,routingConfig.routingMode)'
gcloud compute networks subnets list --filter='network~oil-vpc' \
  --format='table(name,region,ipCidrRange,privateIpGoogleAccess)'
```

Confirm the firewall matrix, in particular that nothing internal is public:

```bash
gcloud compute firewall-rules list --filter='network~oil-vpc' \
  --format='table(name,direction,priority,sourceRanges.list(),targetTags.list(),allowed[].map().firewall_rule().list())'
```

Expected: `0.0.0.0/0` appears only on `oil-deny-all-ingress` and on
`oil-allow-ui-public`, and the latter carries `80,443` and nothing else. Neither
the database port nor the application ports appear on any rule whose source is a
public range.

Once the UI instance exists and carries the `oil-ui` tag, the public side is two
open ports and no more:

```bash
nc -vz -w 5 <ui-public-ip> 443   # succeeds
nc -vz -w 5 <ui-public-ip> 8080  # must time out
nc -vz -w 5 <ui-public-ip> 22    # must time out
```

Prove the database port is not reachable from outside - this must time out:

```bash
nc -vz -w 5 <bastion-public-ip> 5432
```

Check outbound connectivity from a private instance (through the bastion, see the
[bastion README](../bastion/README.md)):

```bash
gcloud compute routers nats describe oil-nat --router=oil-router --region=europe-central2
ssh -J <user>@<bastion-ip>:18832 -p 18832 <user>@<private-ip> 'curl -sS -o /dev/null -w "%{http_code}\n" https://api.github.com'
```

A `200` proves egress works; an inbound connection attempt to the same instance
from the internet has no route and no rule, so it cannot succeed.
