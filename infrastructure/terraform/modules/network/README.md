# Network module

Creates the OilScope VPC foundation: management and workload subnets, Cloud
NAT, and role-based firewall rules for Bastion, Infra, History, Fetcher, and
UI.

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

The bastion and workload modules must attach the tag matching each VM's role.
The firewall contract does not use generic `app` or `db` tags.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | Custom-mode regional VPC without automatic subnets |
| `<prefix>-management` | Management subnet used by the bastion |
| `<prefix>-workload` | Application workload subnet with Private Google Access enabled |
| `<prefix>-router`, `<prefix>-nat` | Outbound internet access for the workload subnet |

## Ingress firewall contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `<prefix>-allow-bastion-ssh` | `bastion_allowed_cidrs` | Bastion | `bastion_ssh_port` |
| `<prefix>-allow-workload-ssh` | Bastion | Infra, History, Fetcher, UI | `22` |
| `<prefix>-allow-history-api` | UI | History | `history_api_port` |
| `<prefix>-allow-postgresql` | Fetcher, History, UI | Infra | `postgresql_port` |
| `<prefix>-allow-ui-web` | `0.0.0.0/0` | UI | `ui_public_ports` (`80` and `443`) |

This matrix follows the current deployment configuration:

- UI calls the History API;
- Fetcher, History, and UI connect directly to PostgreSQL on Infra;
- Fetcher port `8002` is used by its local container health check only;
- UI port `8080` remains inside the UI VM's Docker network behind Traefik.

Consequently, there are no VPC ingress rules for `6379`, `8002`, `8080`, or
`15672`. Other ingress is blocked by Google Cloud's implied deny-ingress rule.

## Egress

Cloud NAT applies to the workload subnet. Egress remains permissive through
Google Cloud's implied allow-egress rule.

## Usage

```hcl
module "network" {
  source = "./modules/network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr
  ui_public_ports        = ["80", "443"]

  bastion_ssh_port      = local.bastion_vm.ssh_port
  bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql
}
```

The module outputs the management and workload subnet IDs and the role-based
`network_tags` map.

## Access procedure

Add an operator's office or VPN CIDR to `bastion_allowed_cidrs`. The resulting
administration path is:

```text
operator -> bastion -> private workload VM
private workload VM -> Cloud NAT -> internet
```

Workload SSH is accepted only from instances carrying the bastion network tag.
PostgreSQL and the History API have role-tag sources and are not reachable
directly from the internet.
