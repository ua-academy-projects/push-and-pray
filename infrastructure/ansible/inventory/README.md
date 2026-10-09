# Inventory

`oilscope.yml` builds the deployment inventory from live cloud state across
every provider the cluster configuration uses, so a `terraform apply` that
replaces a VM or changes an address is picked up without editing a host list.

Every environment-specific value is derived from the cluster configuration
JSON that Terraform also reads, so this file is identical for every
environment — point `OILSCOPE_PROJECT_CONFIG` at a different configuration and
it describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

`oilscope.cluster.oilscope_cloud` talks to no cloud itself. It reads the
cluster configuration, works out which clouds actually host nodes, derives
the settings below for each of them, and hands each set to the discovery plugin
that speaks to that provider:

| Cloud | Discovery plugin | Collection |
| --- | --- | --- |
| `gcp` | `google.cloud.gcp_compute` | `google.cloud` |
| `aws` | `amazon.aws.aws_ec2` | `amazon.aws` |
| `azure` | `azure.azcollection.azure_rm` | `azure.azcollection` |

Hosts from every cloud land in one inventory, in the same role groups.

The wrapper exists because no discovery plugin can read the cluster
configuration, and none evaluates Jinja in its own configuration file — a
template expression placed there is sent to the API as literal text.

| Derived from the JSON | Becomes on GCP | Becomes on AWS | Becomes on Azure |
| --- | --- | --- | --- |
| `clouds.<cloud>.project_id` | the project queried | — | — |
| `clouds.<cloud>.subscription_id` | — | — | the subscription queried |
| `name_prefix` + `environment` | — | — | the resource group `<name_prefix>-<environment>-rg` queried |
| `clouds.<cloud>.zone` | the zone queried | — | — |
| `clouds.<cloud>.region` | — | the region queried | — |
| `name_prefix` | `labels.application` filter | `tag:application` filter | `tags.application` condition |
| `environment` | `labels.environment` filter | `tag:environment` filter | `tags.environment` condition |
| the cloud's own name | `labels.cloud` filter | `tag:cloud` filter | `tags.cloud` condition |
| `bastion.ssh_port`, 22 when absent | the bastion's `ansible_port` | same | same |

`azure_rm` has no server-side filter: it lists every VM in the resource group
and the tag conditions are applied on the controller, together with its
default filter that drops VMs which are not running.

## Which clouds are queried

A node's cloud is its own `cloud`, or `default_cloud` when it sets none — the
rule Terraform applies too. A cloud is queried only when it hosts at least one
node: Terraform builds nothing, not even the bastion, on a cloud without one,
so there is nothing to discover either.

## Groups

Terraform labels every VM with `role=<role>`, which becomes its group:

| Group | Holds |
| --- | --- |
| `bastion` | One bastion per cloud that hosts a node - its Tailscale subnet router |
| `k3s_server` | Nodes with `role: k3s_server` |
| `k3s_agent` | Nodes with `role: k3s_agent` |
| `nodes` | Every node, whatever its role |

Bastions are named `<name_prefix>-<environment>-bastion-<cloud>`, so the three
of them stay three hosts rather than collapsing into one.

## Host variables

Set on every host: `internal_ip`, `public_ip`, `oilscope_role`,
`oilscope_cloud`, `ansible_host`, `ansible_port`, `oilscope_ssh_port`.

A bastion is reached on its public address; a node on its internal one. For
the bastion, `oilscope_ssh_port` is always the final port from
`bastion.ssh_port`; `ansible_port` normally uses the same value, but can use
`OILSCOPE_BASTION_CONNECT_PORT` during the one-time bootstrap connection.

Raw instance fields from the API are prefixed with `gcp_` or `aws_`, because
two of them — `name` and `tags` — collide with names Ansible reserves.
`azure_rm` has no prefix option, so Azure hosts carry `name`, `tags` and the
rest of its fields unprefixed.

## Group variables

| File | Sets |
| --- | --- |
| `all.yml` | SSH user and key, `project_config_path` from `OILSCOPE_PROJECT_CONFIG`, and `oilscope_config` - the decoded configuration |
| `bastion.yml` | The bastion's SSH port and its Tailscale settings: the port and tags from `tailscale`, the route from its own cloud's `network_cidr`, `accept_routes` once nodes run on more than one cloud |
| `nodes.yml` | How a node is reached - see [SSH](#ssh) |

## Setup

All of these are required, and skipping one produces a failure that does not
name the missing piece:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
gcloud auth application-default login
```

For Azure, the `azure_rm` plugin imports the whole Azure SDK its collection
pins, and `az login` provides the credential:

```sh
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt
az login
```

Install that list into the Python environment Ansible runs from. It pins its
own `azure-cli-core`, so keep it away from the environment the `az` command
itself lives in.

`ansible-galaxy` installs collections, never Python packages, and `pip` the
reverse, so neither file covers for the other.

## Pointing it at your configuration

`oilscope.yml` carries no path of its own, because the cluster configuration
does not live in the same place for everyone. Export it once:

```sh
export OILSCOPE_PROJECT_CONFIG=/absolute/path/cluster-config.json
ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph
```

The variable feeds both the plugin and `group_vars/all.yml`, so every later
inventory, ad-hoc and playbook command reads the same file. An absolute path is
used as given; a relative one is tried by the plugin against the working
directory first, then against this directory - prefer absolute, since the
group variables resolve it against the working directory only.

Adding `project_config_path` into `oilscope.yml` would pin the path for
everyone **and** make the variable ineffective for the plugin, since a value
set in the file wins over the environment. Keep personal paths in the variable,
or in a local `*oilscope.yml` of your own — the filename only has to end in
`oilscope.yml` for the plugin to claim it, and `local.oilscope.yml` is already
ignored by git.

Hosts appear only after `terraform apply`: the inventory reports what exists in
the clouds, so before the infrastructure is created it is legitimately empty.

## SSH

The bastion is reached on its public address. Nodes are reached **over the
tailnet**: each bastion advertises its cloud's `network_cidr`, so a controller
joined to the tailnet with routes accepted connects to a node's internal
address directly, without a tunnel. On Linux, accept routes once:

```sh
sudo tailscale set --accept-routes
```

The subnet routers keep source addresses, so a node sees the controller's
tailnet address; the cloud firewalls admit SSH from `tailscale.address_range`,
and every cloud routes that range back through its bastion.

Before the bastions run Tailscale - the first deployment - or while the tailnet
is down, hop through the bastion of the node's own cloud instead:

```sh
ansible-playbook ... -e oilscope_nodes_via_bastion=true
```

The order on a fresh environment is therefore: the bastions first, reached on
their public addresses, then everything else over the tailnet.

### Moving the bastion's SSH port

Terraform does not configure `sshd`. A newly created bastion starts on port
22, and the `bastion` role moves it to `bastion.ssh_port`. When that differs
from 22:

1. Apply Terraform with the temporary port-22 rule enabled. The rule is
   restricted to `bastion.allowed_cidrs`, targets only the bastion, and is
   not created when the final port is already 22.

```sh
terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path="$OILSCOPE_PROJECT_CONFIG" \
  -var=enable_bastion_ssh_bootstrap=true
```

2. Run the bastion role with `OILSCOPE_BASTION_CONNECT_PORT=22`, then unset it.
3. Apply Terraform again without the bootstrap variable; its default is
   `false`, so the temporary rule goes away without touching any VM.

`ansible_user` (in `group_vars/all.yml`) defaults to the controller's own login
name. Override it for one run with `OILSCOPE_SSH_USER`, and the key with
`OILSCOPE_SSH_KEY`.

## When it looks broken

| Symptom | Cause |
| --- | --- |
| `No inventory was parsed`, doubled path in the message | not run from the repository root |
| `unknown plugin 'oilscope.cluster.oilscope_cloud'` | this repository's collection is not on the collections path |
| `unknown plugin 'google.cloud.gcp_compute'` | `requirements.yml` not installed |
| `cannot start: ... library (google-auth)` | `requirements.txt` not installed |
| `must define a 'nodes' object` | the JSON is the old Docker Compose configuration with `vms` |
| **Empty `@all`, exit status 0** | `project_id`, `zone` or the labels do not match reality |
| Node unreachable, bastion fine | the controller is not in the tailnet, does not accept routes, or the bastion's route is not approved yet - or use `oilscope_nodes_via_bastion=true` |
| `Permission denied (publickey)` | the account is absent from `ssh_users`, or the wrong key |

The empty-inventory case is the dangerous one: the delegate swallows API
errors, so a wrong project or zone looks exactly like a working inventory with
nothing in it. Check against the cloud directly rather than trusting the graph:

```sh
gcloud compute instances list --format="table(name,zone,labels)"
```

`azure_rm` behaves the same way: a resource group that does not exist, or a
credential without Reader on it, yields an empty inventory and exit status 0.

```sh
az vm list -g oilscope-dev-rg --query "[].{name:name, tags:tags}" -o table
```
