# Network module

Creates the OilScope VPC foundation: management and workload subnets, explicit
routing, Cloud NAT and role-based firewall rules for Bastion, Infra, History,
Fetcher and UI.

## Network tags

The module exports one tag for every VM role:

```hcl
network_tags = {
  bastion = "<prefix>-bastion"
  infra   = "<prefix>-infra"
  history = "<prefix>-history"
  fetcher = "<prefix>-fetcher"
  ui      = "<prefix>-ui"
}
```

The bastion module consumes `network_tags.bastion`. Root workload compute
derives the matching tag from each VM's JSON `role` and appends it to any
additional `network_tags`. Firewall selection therefore cannot drift when a
display name or optional tag changes.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | Custom-mode VPC without automatic subnets |
| `<prefix>-subnet-public` | Management subnet used by the bastion; GCP name retained for state compatibility |
| `<prefix>-subnet-private` | Application workload subnet; GCP name retained for state compatibility |
| `<prefix>-rt-default-internet` | Optional explicitly managed default route |
| `<prefix>-router`, `<prefix>-nat` | Outbound internet access for the workload subnet |

## Ingress firewall contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `allow-ssh-to-bastion` | `bastion_allowed_cidrs` | Bastion | `ssh_port` |
| `allow-ssh-from-bastion` | Bastion | Infra, History, Fetcher, UI | `ssh_port` |
| `allow-history-api-from-ui` | UI | History | `8001` by default |
| `allow-postgresql-to-infra` | Fetcher, History, UI | Infra | `5432` by default |
| `allow-ui-public` | `ui_source_ranges` | UI | `80`, `443` by default |
| `allow-internal-icmp` | VPC subnet ranges | All five roles | ICMP |
| `deny-all-ingress` | `0.0.0.0/0` | All instances | All denied |

This matrix follows the PostgreSQL-only deployment configuration:

- UI calls the History API;
- Fetcher publishes queue events through PostgreSQL on Infra;
- History consumes queue events and stores observations in PostgreSQL;
- UI stores sessions in PostgreSQL;
- Fetcher port `8002` is used by its local container healthcheck only;
- UI port `8080` remains inside the UI VM's Docker network behind Traefik.

Consequently, there are no VPC ingress rules for `8002` or `8080`.
`ui_public_ports` is validated as exactly `80` and `443`, so an internal
application port cannot be added to the public rule.

## Egress

Cloud NAT applies to the workload subnet and is unchanged by the role-based
ingress contract. Egress remains permissive through GCP's implied rule by
default.

When `restrict_egress = true`, the module adds the existing allow rules for
in-VPC traffic, metadata, DNS/NTP and configured internet TCP ports, followed
by an explicit deny-all egress rule. This opt-in behavior is intentionally not
role-specific.

## Usage

```hcl
module "network" {
  source = "./modules/network"

  project_id  = local.config.project_id
  region      = local.config.region
  name_prefix = local.name_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  postgresql_port     = local.config.network.service_ports.postgresql
  history_api_port    = local.config.network.service_ports.history_api
  fetcher_health_port = local.config.network.service_ports.fetcher_health
  ui_internal_port    = local.config.network.service_ports.ui_internal
  ui_public_ports     = [for port in local.config.network.ui_public_ports : tostring(port)]
  ui_source_ranges    = local.config.network.ui_source_ranges

  ssh_port              = local.config.bastion.ssh_port
  bastion_allowed_cidrs = local.config.bastion.bastion_allowed_cidrs
}
```

Important inputs include subnet CIDRs, `ssh_port`,
`bastion_allowed_cidrs`, `history_api_port`, `postgresql_port`, internal
service ports used for public-port validation, UI
ingress settings, NAT settings and the optional egress restrictions.

Important outputs include VPC/subnet identifiers, `network_tags`, NAT details,
firewall rule names and the configured service ports.

## Access procedure

Add an operator's office or VPN CIDR to `bastion_allowed_cidrs` and their
public key to the bastion module's `ssh_users`. The resulting administration
path is:

```text
operator -> bastion -> private workload VM
private workload VM -> Cloud NAT -> internet
```

Public SSH on port 22 is never opened. PostgreSQL and the History API have
role-tag sources only and are not reachable directly from the internet.
