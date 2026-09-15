# GCP firewall module

Owns the ingress contract for one GCP deployment: which role may reach which
role, on which port. It creates the rules and defines the network tags they
match on.

Separate from the [network module](../network/README.md) on all three counts
the Terraform module guidance names:

- **Encapsulation** - a VPC and its subnets are deployed once and never
  change; these rules change whenever the application gains a port.
- **Privileges** - editing a CIDR layout and editing "who may reach PostgreSQL"
  are different responsibilities.
- **Volatility** - the network is long-lived, the contract is not.

The only thing it needs from the network is `network_id`.

## Network tags

The module owns the tag namespace and exports it:

```hcl
network_tags = {
  bastion = "<prefix>-bastion"
  infra   = "<prefix>-infra"
  history = "<prefix>-history"
  fetcher = "<prefix>-fetcher"
  ui      = "<prefix>-ui"
}
```

The VM module attaches the tag matching each VM's role. The contract does not
use generic `app` or `db` tags.

## Ingress contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `<prefix>-allow-bastion-ssh` | `bastion.allowed_cidrs` | Bastion | `bastion.ssh_port` |
| `<prefix>-allow-bastion-ssh-bootstrap` | `bastion.allowed_cidrs` | Bastion | `22` (temporary and opt-in) |
| `<prefix>-allow-workload-ssh` | Bastion | Infra, History, Fetcher, UI | `22` |
| `<prefix>-allow-history-api` | UI | History | `config.service_ports.history_api` |
| `<prefix>-allow-postgresql` | Fetcher, History, UI | Infra | `config.service_ports.postgresql` (self-hosted database only) |
| `<prefix>-allow-amqp` | Fetcher, History, UI | Infra | `config.service_ports.amqp` (managed database only) |
| `<prefix>-allow-redis` | Fetcher, History, UI | Infra | `config.service_ports.redis` (managed database only) |
| `<prefix>-allow-ui-web` | `0.0.0.0/0` | UI | `config.network.ui_public_ports` (`443` only) |

What the infra VM serves follows `database_managed`: with a self-hosted
database it runs PostgreSQL, with a managed one it runs the RabbitMQ broker and
the Redis cache instead, so the three rules swap as one. The managed database
itself needs no rule: its Private Service Connect endpoint is not a VM, and
egress from the VPC is allowed by default.

Port 80 is deliberately closed. Traefik terminates TLS on 443 and solves the
ACME challenge with TLS-ALPN-01, so nothing ever listens on 80; opening it
would expose a port with no service behind it.

There are likewise no rules for `8002`, `8080` or `15672` - Fetcher's
`8002` serves its local container health check only, and UI's `8080` stays
inside the UI VM's Docker network behind Traefik. Everything else is blocked by
Google Cloud's implied deny-ingress rule.

## The bootstrap rule

Disabled by default. When `enable_bastion_ssh_bootstrap` is true it is created
only if the final SSH port is not already `22`. It uses the same operator CIDRs
and bastion target tag as the final rule. Remove it immediately after Ansible
has configured and verified the final port.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every rule name and tag |
| `network_id` | The VPC these rules apply to |
| `config` | Project configuration; only `network.ui_public_ports` and `service_ports` are read |
| `bastion` | The project-wide `bastion` block: its `ssh_port` and `allowed_cidrs` |
| `enable_bastion_ssh_bootstrap` | Opt in to the temporary port 22 rule |

## Outputs

| Name | Description |
| --- | --- |
| `network_tags` | Role to tag map, consumed by the VM module |
| `firewall_rule_names` | Every rule by purpose; the bootstrap entry is absent unless enabled |
| `scopes` | The role scopes this contract is written in terms of |

## Usage

```hcl
module "firewall" {
  source = "./modules/firewall"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  network_id      = module.network[0].network_id
  config          = var.config
  bastion         = var.config.bastion

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}
```

## Access procedure

Add an operator's office or VPN CIDR to `bastion.allowed_cidrs` in the project
configuration. The resulting administration path is:

```text
operator -> bastion -> private workload VM
private workload VM -> Cloud NAT -> internet
```

Workload SSH is accepted only from instances carrying the bastion tag.
PostgreSQL and the History API have role-tag sources and are unreachable from
the internet.

## License

GPL-2.0-or-later
