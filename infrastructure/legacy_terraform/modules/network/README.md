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

The bastion module consumes `network_tags.bastion`. Future workload compute
must attach the tag matching its role. The firewall contract does not use
generic `app` or `db` tags.

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
| `allow-postgresql-to-infra` | History | Infra | `5432` by default |
| `allow-ui-public` | `ui_source_ranges` | UI | `80`, `443` by default |
| `allow-internal-icmp` | VPC subnet ranges | All five roles | ICMP |
| `deny-all-ingress` | `0.0.0.0/0` | All instances | All denied |

This matrix follows the current deployment configuration:

- UI calls the History API;
- History connects directly to PostgreSQL on Infra;
- Fetcher and History connect directly to PostgreSQL on Infra;
- UI still uses Redis for session preferences, but the working Vagrant
  deployment co-locates Redis with UI on a Docker network, so it is not an
  inter-VM firewall dependency;
- the cloud deployment Compose currently supplies unused `DATABASE_URL`
  values to Fetcher and UI and omits the Redis service required by UI code;
- Fetcher port `8002` is used by its local container healthcheck only;
- UI port `8080` remains inside the UI VM's Docker network behind Traefik.

Consequently, there are no VPC ingress rules for `6379`, `8002`, `8080` or
`15672`.

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

  project_id  = var.project_id
  region      = var.region
  name_prefix = local.name_prefix

  ssh_port              = var.ssh_port
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
}
```

Important inputs include subnet CIDRs, `ssh_port`,
`bastion_allowed_cidrs`, `history_api_port`, `db_port`, UI
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

Public SSH on port 22 is never opened. PostgreSQL and the History API
have role-tag sources only and are not reachable directly from the internet.
