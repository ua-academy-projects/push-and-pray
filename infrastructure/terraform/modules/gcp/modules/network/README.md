# GCP network module

Creates the VPC foundation for one GCP deployment: a custom-mode network,
management and workload subnets, Cloud NAT, and role-based firewall rules for
Bastion, Infra, History, Fetcher and UI.

The module is called once per active cloud. It never sees the VM list - only
the subnet ranges from the cloud profile, the shared service ports, and the
bastion's externally reachable SSH settings.

## Network tags

The module exports one tag per role:

```hcl
network_tags = {
  bastion = "<prefix>-bastion"
  infra   = "<prefix>-infra"
  history = "<prefix>-history"
  fetcher = "<prefix>-fetcher"
  ui      = "<prefix>-ui"
}
```

The VM module attaches the tag matching each VM's role. The firewall contract
does not use generic `app` or `db` tags.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | Custom-mode regional VPC without automatic subnets |
| `<prefix>-management` | Management subnet used by the bastion |
| `<prefix>-workload` | Workload subnet with Private Google Access enabled |
| `<prefix>-router`, `<prefix>-nat` | Outbound internet access for the workload subnet |

## Ingress firewall contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `<prefix>-allow-bastion-ssh` | `bastion.allowed_cidrs` | Bastion | `bastion.ssh_port` |
| `<prefix>-allow-bastion-ssh-bootstrap` | `bastion.allowed_cidrs` | Bastion | `22` (temporary and opt-in) |
| `<prefix>-allow-workload-ssh` | Bastion | Infra, History, Fetcher, UI | `22` |
| `<prefix>-allow-history-api` | UI | History | `config.service_ports.history_api` |
| `<prefix>-allow-postgresql` | Fetcher, History, UI | Infra | `config.service_ports.postgresql` |
| `<prefix>-allow-ui-web` | `0.0.0.0/0` | UI | `config.network.ui_public_ports` (`443` only) |

Port 80 is deliberately closed. Traefik terminates TLS on 443 and solves the
ACME challenge with TLS-ALPN-01, so nothing ever listens on 80; opening it
would expose a port with no service behind it.

There are likewise no rules for `6379`, `8002`, `8080` or `15672` - Fetcher's
`8002` serves its local container health check only, and UI's `8080` stays
inside the UI VM's Docker network behind Traefik. Everything else is blocked by
Google Cloud's implied deny-ingress rule.

## Egress

Cloud NAT applies to the workload subnet. Egress stays permissive through
Google Cloud's implied allow-egress rule - unlike AWS, where the equivalent
module has to grant egress explicitly.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every resource name |
| `profile` | Cloud profile; only `subnets.management` and `subnets.workload` are read |
| `config` | Project configuration; only `network.ui_public_ports` and `service_ports` are read |
| `bastion` | The bastion's `ssh_port` and `allowed_cidrs` |
| `enable_bastion_ssh_bootstrap` | Opt in to the temporary port 22 rule |

`profile` and `config` are declared as narrow object types, so the caller
passes the whole object and the type documents exactly what is used.

## Outputs

| Name | Description |
| --- | --- |
| `network_id`, `network_name`, `network_self_link` | The VPC |
| `region` | Region both subnets live in, derived from the provider |
| `management_subnet_id`, `_name`, `_cidr`, `_gateway` | Bastion subnet |
| `workload_subnet_id`, `_name`, `_cidr`, `_gateway` | Workload subnet |
| `router_name`, `nat_name` | Cloud Router and Cloud NAT |
| `network_tags` | Role to tag map, consumed by the VM module |
| `firewall_rule_names` | Every ingress rule by purpose; the bootstrap entry is absent unless enabled |

## Usage

```hcl
module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  config          = var.config
  profile         = local.profile
  bastion         = local.bastion_vm

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}
```

## Access procedure

Add an operator's office or VPN CIDR to the bastion's `allowed_cidrs` in the
project configuration. The resulting administration path is:

```text
operator -> bastion -> private workload VM
private workload VM -> Cloud NAT -> internet
```

Workload SSH is accepted only from instances carrying the bastion tag.
PostgreSQL and the History API have role-tag sources and are unreachable from
the internet.

The bootstrap rule is disabled by default. When `enable_bastion_ssh_bootstrap`
is true it is created only if the final SSH port is not already `22`. It uses
the same operator CIDRs and bastion target tag as the final rule. Remove it
immediately after Ansible has configured and verified the final port.

## License

GPL-2.0-or-later
