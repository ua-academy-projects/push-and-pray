# Inventory

> **`oilscope-aws.yml` no longer works the way this document describes.** The AWS
> plugin was rewritten for k3s: there is no bastion, no `ProxyCommand`, no
> `bastion_role` option and no `OILSCOPE_BASTION_CONNECT_PORT`. Every node is
> contacted directly on its public address, hosts are grouped into `k3s_servers`
> and `k3s_workers` from the `<name_prefix>-control-plane` and
> `<name_prefix>-worker` instance tags — both groups holding all three nodes —
> and `OILSCOPE_SSH_KEY` is **required** rather than defaulted.
>
> Everything below still describes `oilscope.yml` (GCP) and
> `oilscope-azure.yml` (Azure), which have not been converted. Read it with that
> split in mind until they are, at which point the bastion material goes
> entirely.

`oilscope.yml` (GCP), `oilscope-aws.yml` (AWS) and `oilscope-azure.yml`
(Azure) build the deployment inventory from live cloud state, so a `terraform apply` that replaces a VM or
changes an address is picked up without editing a host list. Use whichever
one matches `default_cloud` in your project configuration.

Every environment-specific value is derived from the project configuration
JSON that Terraform also reads, so each of these files is identical for every
environment — point `project_config_path` at a different configuration and it
describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

None of `oilscope.platform.oilscope_gcp`, `oilscope.platform.oilscope_aws` or
`oilscope.platform.oilscope_azure` talks to its cloud directly. Each reads the
project configuration, derives the settings below, and hands them to the
matching upstream plugin — `google.cloud.gcp_compute`, `amazon.aws.aws_ec2` or
`azure.azcollection.azure_rm` — which performs the discovery.

The wrapper exists because no upstream plugin can read the project
configuration or evaluate Jinja in its own configuration file — a template
expression placed there is sent to the API as literal text.

All three wrappers expose the same contract on every host, regardless of cloud:
`oilscope_cloud` (`gcp`, `aws` or `azure`), `oilscope_vm_key` (this VM's key in the
configuration's `vms` object, recovered from the instance's own name/tag —
not from `inventory_hostname`, which a custom `hostnames` setting or a static
test inventory could give an unrelated value), `oilscope_role`, `internal_ip`,
`public_ip`, `ansible_host`, and `bastion_ssh_port`. Roles that need a VM's
own configuration entry (`resolve_secrets`, `secret_versions`) read
`oilscope_vm_key`, not `inventory_hostname`. A discovered instance that
doesn't map back to a `vms` entry — wrong `name_prefix`/`environment`, or a
renamed VM — fails inventory parsing immediately rather than silently
producing a host with no secret mappings.

Each wrapper also sets the SSH connection variables itself, in Python, once
its delegate has finished discovering hosts: `ansible_user`,
`ansible_ssh_private_key_file` and `ansible_ssh_common_args` on every host,
`ansible_port` on the bastion, and on each workload a `ProxyCommand` through
the bastion (plus `oilscope_bastion_address`/`oilscope_bastion_ssh_port` as
data). There is deliberately no `group_vars/` directory here.

Two things force that placement. A workload's `ProxyCommand` needs the
bastion's *discovered* address, and a `compose` expression only ever sees the
one host it is composing — so it cannot be composed. And `ansible_port` has
to honour `OILSCOPE_BASTION_CONNECT_PORT` during first-boot bootstrap, so the
override has to be read wherever the value is produced; reading it in Python
alongside the port itself keeps that in one place instead of splitting the
connection contract across files named after groups the plugin invents.

Note that the bastion's own `ansible_port` and the workloads' hop port are
not the same value: the override moves only the port Ansible dials on the
bastion directly, while the `ProxyCommand` keeps using the configured
`ssh_port`, which is where sshd ends up once `bootstrap_bastion.yml` has run.

### GCP (`oilscope.yml`)

| Derived from the JSON | Becomes |
| --- | --- |
| `clouds.gcp.project_id` | the project queried |
| `region_map[region].gcp.zone` | the zone queried |
| `name_prefix` | the `labels.application` filter |
| `environment` | the `labels.environment` filter |
| `ssh_port` of the VM whose `role` is `bastion` | the bastion's `bastion_ssh_port` |

### AWS (`oilscope-aws.yml`)

| Derived from the JSON | Becomes |
| --- | --- |
| `region_map[region].aws.region` | the region queried |
| `name_prefix` | the `tag:application` filter |
| `environment` | the `tag:environment` filter |
| `ssh_port` of the VM whose `role` is `bastion` | the bastion's `bastion_ssh_port` |

### Azure (`oilscope-azure.yml`)

| Derived from the JSON | Becomes |
| --- | --- |
| `clouds.azure.subscription_id` | the subscription queried |
| `clouds.azure.resource_group_name` | the only resource group searched |
| `region_map[region].azure.location` | part of the single include filter |
| `name_prefix` | the `tags.application` check in that filter |
| `environment` | the `tags.environment` check in that filter |
| `ssh_port` of the VM whose `role` is `bastion` | the bastion's `bastion_ssh_port` |

Azure differs from the other two in one way worth knowing: `azure_rm`'s
`include_host_filters` entries are **ORed**, so location, application and
environment are combined into one `and` expression rather than listed
separately. Three entries would admit any VM matching any one of them — the
opposite of what the other two clouds' filter lists do.

`plain_host_names` is on, so a host appears under its VM name rather than a
name with a hash suffix. That is presentation only: `oilscope_vm_key` is still
derived from the VM's own `name`, never from the inventory alias.

Everything else — the grouping rules, the host-variable expressions, the
workload SSH port — lives in each plugin's defaults. Changing those means
editing the plugin and rebuilding the collection, not editing this directory.

## Setup

### GCP

All three steps are required, and skipping one produces a failure that does not
name the missing piece:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
gcloud auth application-default login
```

`requirements.yml` installs the `google.cloud` collection, which provides the
`gcp_compute` plugin this one delegates to. `requirements.txt` installs the
Python libraries that plugin imports at run time — `google-auth` and
`requests`. `ansible-galaxy` installs collections, never Python packages, so
neither file covers for the other.

### AWS

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

`requirements.yml` installs the `amazon.aws` collection, which provides the
`aws_ec2` plugin `oilscope_aws` delegates to. `requirements.txt` installs the
`boto3`/`botocore` libraries that plugin imports at run time. There is no
separate login step: `amazon.aws` authenticates through the standard boto3
credential chain, so whatever already makes the AWS CLI work on your machine
(`~/.aws/credentials`, `AWS_PROFILE`, an assumed role, ...) is enough.

### Azure

```sh
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt
az login
```

`requirements.yml` installs `azure.azcollection`, which provides the
`azure_rm` plugin `oilscope_azure` delegates to. Its Python dependencies are
**not** in this repository's `requirements.txt`, unlike the other two clouds:
that collection's `module_utils` imports its whole SDK surface inside a single
`try` block, so a partial install leaves the plugin unusable with a message
naming none of the packages actually missing. Install its own requirements
file, as above.

`az login` is one way to authenticate; `ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`,
`ARM_TENANT_ID` and `ARM_CLIENT_SECRET` in the environment are another, and
`auth_source: auto` accepts either.

**`OILSCOPE_SSH_KEY` is required on Azure.** With it unset the shared helper
falls back to `~/.ssh/google_compute_engine`, a gcloud-managed key that is
never provisioned on an Azure VM — so every host fails to authenticate with a
message about the key, not about the cloud.

### All three

This repository's own collection must also be installed, because there is no
`ansible.cfg` pointing Ansible at the working copy:

```sh
cd infrastructure/ansible/oilscope/platform && ansible-galaxy collection build --force && ansible-galaxy collection install oilscope-platform-*.tar.gz --force
```

Repeat that after every change to the plugin or to a role — Ansible reads the
installed copy, not the files you just edited.

## Pointing it at your configuration

None of `oilscope.yml`, `oilscope-aws.yml` or `oilscope-azure.yml` carries a
path of its own,
because the project configuration does not live in the same place for
everyone. The path is resolved in three steps, weakest first:

1. the plugin's default, `../../terraform/env/dev.json`, relative to this
   directory;
2. the `OILSCOPE_PROJECT_CONFIG` environment variable;
3. a `project_config_path` key written into the inventory file.

So a configuration kept elsewhere needs no edit to a committed file:

```sh
OILSCOPE_PROJECT_CONFIG=infrastructure/terraform/env/mine.json \
  ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph
```

Export it once and every later command picks it up. An absolute path is used as
given; a relative one is tried against the working directory first, then
against this directory, so a path typed from the repository root works.

Adding `project_config_path` back into `oilscope.yml` would pin the path for
everyone **and** make the variable ineffective, since a value set in the file
wins over the environment. Keep personal paths in the variable, or in a local
`*oilscope.yml` of your own — the filename only has to end in `oilscope.yml`
for the plugin to claim it, and `local.oilscope.yml` is already ignored by git.

## Usage

```sh
# GCP
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json \
  --graph

# AWS
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json \
  --graph

# Azure
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope-azure.yml \
  -e project_config_path=/absolute/path/project-config.json \
  --graph
```

Use whichever file matches the configuration's `default_cloud` (and every
`vms.*.cloud` override, if any are set). Hosts appear only after
`terraform apply`: the inventory reports what exists in the cloud, so before
the infrastructure is created it is legitimately empty.

That last point is also why an incomplete or empty discovery cannot be
allowed to look like a normal, uneventful run once infrastructure *does*
exist: Ansible does not treat a failed inventory source as fatal by
default — a plugin that raises during parsing is downgraded to a warning,
and a play whose hosts then don't exist is silently skipped, exit code 0.
Worse: a host a plugin already added to the shared inventory before it
raised stays live and targetable regardless — the plugins' own
`validate_inventory_hosts` rejecting a host is not, on its own, enough to
stop a later play from running against it.

Every playbook here imports `preflight.yml` first specifically to close that
gap - for real, not just cosmetically. Its checks (in
`playbooks/tasks/preflight_checks.yml`) fail the whole run, hard, if: the
configuration resolves to more than one cloud; any VM it expects wasn't
discovered at all; a discovered host's role/cloud doesn't match what the
configuration says for its own VM key; two hosts claim the same VM key; or a
host is missing from the Ansible group its own role implies (every
deployment play targets a role's group by name, so a host absent from it is
silently skipped rather than deployed to, exactly like the empty-discovery
case). See [SSH](#ssh) below for its other check.

These checks run from two plays - one scoped to `localhost` (which always
exists, even when discovery totally fails), one to `all` (so `--limit` still
intersects it correctly) - because `--limit` can exclude `localhost`
specifically and skip the first outright. Even that isn't quite complete:
if `--limit` excludes *every* host in *both* plays, neither runs at all, and
nothing inside Ansible's own execution model is left to catch it. That's
what [`deploy.sh`](../deploy.sh) is for — see
[oilscope/platform/README.md](../oilscope/platform/README.md#deploy-all-workloads).

## Groups

Terraform labels/tags every VM with `role=<role>`, which becomes the
`bastion`, `database`, `history`, `fetcher` and `ui` groups the deployment
roles expect. Everything except the bastion also joins `workloads`.

The group name comes from the `role` label/tag, not from the key in the
project configuration: `vms.infra` has `role: database` and therefore lands
in the `database` group, which is what the `ui` role looks for.

## Host variables

`internal_ip` is set on every host. This is a contract, not a convenience: the
`ui` role resolves its Database and History peers through that exact variable
name. Also set: `public_ip`, `oilscope_role`, `oilscope_cloud`,
`oilscope_vm_key`, `ansible_host`, `bastion_ssh_port` — see
[How it fits together](#how-it-fits-together) for what each one means and
guarantees.

`ansible_port` is set on the bastion only. The plugin derives it from that
VM's `ssh_port`, honoring `OILSCOPE_BASTION_CONNECT_PORT` during the one-time
bootstrap connection; every workload connects on Ansible's own default of 22,
which is the only port their sshd ever listens on. Workloads additionally
carry `oilscope_bastion_address` and `oilscope_bastion_ssh_port`, the two
values their `ProxyCommand` is built from.

Raw instance fields from the GCP API are prefixed with `gcp_`, because two of
them — `name` and `tags` — collide with names Ansible reserves. AWS's raw
instance fields carry no prefix; `aws_ec2` doesn't have the same collision
(tags are read through `ec2_tags`, not `tags`). Azure's are unprefixed too,
and include `name`, `tags`, `id`, `location`, `resource_group`, `powerstate`,
`private_ipv4_addresses` (a list) and `public_ipv4_address` (a single value,
absent entirely on a private VM). Azure hosts additionally carry
`oilscope_vm_id`, the VM's ARM resource ID.

## SSH

`ansible_user` (set by the inventory plugin) defaults to `OILSCOPE_SSH_USER`,
or the controller's own login name if that isn't set - but it can also come from
`-e ansible_user=...`, a host var, or anywhere else Ansible reads it from.
Whatever the source, it must resolve to one of the usernames in the
configuration's `ssh_users`: all three clouds only ever create the accounts
listed there (via GCP instance metadata, or cloud-init on AWS and Azure),
never the operator's own local account by name. On Azure one of those names
is additionally the platform administrator, named by
`clouds.azure.admin_username`. `preflight.yml`'s second play checks the *effective*
`ansible_user` for every real target host individually - not by re-deriving
it from `OILSCOPE_SSH_USER`/`$USER` itself, which would miss a `-e` or
host-var override - and fails before any real connection is attempted if it
doesn't match. Set `OILSCOPE_SSH_KEY` to the matching private key - there's
no default that's correct for every cloud, since GCP operators traditionally
used the key `gcloud compute ssh` manages at `~/.ssh/google_compute_engine`,
and neither AWS nor Azure has an equivalent auto-managed key at all. On both
of those, `OILSCOPE_SSH_KEY` is effectively required.

The bastion is normally reached on its external address at the final port read
from `vms.bastion.ssh_port` in the project config. Every workload is reached on
its internal address at port 22, through a `ProxyCommand` the inventory plugin
builds from the bastion's discovered address. The ProxyCommand always uses the
bastion's final port; the bootstrap connection override applies only to the
bastion itself. Pass the absolute project config
path on every inventory, ad-hoc and playbook command.

The non-default port belongs to the bastion alone; applying it globally would
break every workload connection.

On AWS and GCP, Terraform does not configure `sshd`. A newly created bastion
therefore starts on port 22, and Ansible changes it to the final configured
port. Use this bootstrap sequence whenever the bastion has not yet been
configured.

**Azure needs none of it.** Its bastion's cloud-init writes the sshd drop-in
during first boot, so the VM serves `vms.bastion.ssh_port` from the start and
the network security group only ever opens that port. There is no window in
which 22 is both needed and open, nothing to enable and nothing to close
afterwards — skip to step 3 and confirm connectivity. `bootstrap_bastion.yml`
is still safe to run there; it just has nothing to change.

**AWS caveat:** unlike GCP's firewall, the AWS bastion security group
(`modules/aws/network/security_groups.tf`) only ever opens the *final*
configured `ssh_port` - there is no temporary port-22 rule to enable. If
`vms.bastion.ssh_port` is `22`, this doesn't matter: the security group
already allows the port Ansible needs for step 2 below. If you configure a
different port, you must open 22 yourself first (temporarily, scoped to
`vms.bastion.allowed_cidrs`, removed again afterwards) before step 2 can
connect at all - there's no automated equivalent of the GCP bootstrap rule on
the AWS side yet.

1. **GCP only.** Apply Terraform with the temporary port-22 rule enabled. The
   rule is restricted to `vms.bastion.allowed_cidrs`, targets only the
   bastion, and is not created when the final port is already 22. On AWS,
   open port 22 yourself first instead - see the caveat above.

```sh
terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path=/absolute/path/project-config.json \
  -var=enable_bastion_ssh_bootstrap=true
```

2. Connect through port 22 and run the bastion playbook. The role validates the
   generated `sshd` configuration before installing it, restarts SSH, waits for
   the final port from the controller, resets the bootstrap connection, and
   verifies Ansible connectivity on the final port.

```sh
export OILSCOPE_BASTION_CONNECT_PORT=22
infrastructure/ansible/deploy.sh oilscope.platform.bootstrap_bastion \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
unset OILSCOPE_BASTION_CONNECT_PORT
```

Substitute `-i infrastructure/ansible/inventory/oilscope-aws.yml` on AWS, or
`oilscope-azure.yml` on Azure.

3. Confirm a new Ansible connection works on the final configured port.

```sh
ansible bastion \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -m ansible.builtin.ping
```

4. **GCP only.** Apply Terraform again without the bootstrap variable. Its
   default is `false`, so Terraform removes the temporary port-22 rule
   without changing any VM. On AWS, close the port-22 rule you opened
   manually in step 1.

```sh
terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path=/absolute/path/project-config.json
```

5. **GCP only.** Confirm the temporary firewall rule no longer exists and
   port 22 is not reachable from an allowed operator address. The exact rule
   name ends in `-allow-bastion-ssh-bootstrap`.

```sh
gcloud compute firewall-rules list \
  --filter='name~allow-bastion-ssh-bootstrap' \
  --format='value(name)'
```

The command must return no rule. Workload playbooks do not use the bootstrap
override; their existing ProxyCommand connects to the bastion through the
final configured port and then reaches workload SSH on port 22.

## When it looks broken

| Symptom | Cause |
| --- | --- |
| `No inventory was parsed`, doubled path in the message | not run from the repository root |
| `unknown plugin 'oilscope.platform.oilscope_gcp'` / `'...oilscope_aws'` / `'...oilscope_azure'` | this repository's collection is not installed, or was not rebuilt |
| `unknown plugin 'google.cloud.gcp_compute'` | `requirements.yml` not installed |
| `unknown plugin 'amazon.aws.aws_ec2'` | `requirements.yml` not installed |
| `unknown plugin 'azure.azcollection.azure_rm'` | `requirements.yml` not installed |
| `cannot start: ... library (google-auth)` | `requirements.txt` not installed (GCP) |
| `No module named 'boto3'` / `'botocore'` | `requirements.txt` not installed (AWS) |
| `Failed to get credentials. Either pass as parameters, set environment variables, ... or log in with Azure CLI` | no `az login` session and no `ARM_*` in the environment |
| an Azure import error naming one SDK package | the collection's own `requirements.txt` was not installed - install all of it, not the one package named |
| `... is not a key in this configuration's vms` | the inventory and the project configuration have drifted apart - wrong `project_config_path`, or a VM was renamed |
| **Empty `@all`, exit status 0** | GCP: `clouds.gcp.project_id` or the zone/labels don't match reality. AWS: the region, or the `application`/`environment` tags, don't match reality. Azure: `clouds.azure.resource_group_name`, the location, or the `application`/`environment` tags don't match reality |
| `'nnn' is not one of this configuration's ssh_users` | `OILSCOPE_SSH_USER` (or your local username) isn't a key in `ssh_users` - the preflight play catches this before any connection is attempted |
| `Permission denied (publickey)` | the account is absent from `ssh_users`, or `OILSCOPE_SSH_KEY` doesn't point at the matching private key |

The empty-inventory case is the dangerous one: the delegate swallows API
errors, so a wrong project/region or a typo'd label/tag looks exactly like a
working inventory with nothing in it. Check against the cloud directly rather
than trusting the graph:

```sh
# GCP
gcloud compute instances list --format="table(name,zone,labels)"

# AWS
aws ec2 describe-instances \
  --filters Name=tag:application,Values=<name_prefix> Name=tag:environment,Values=<environment> \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,Role:Tags[?Key==`role`]|[0].Value}' \
  --output table

# Azure
az vm list -g <resource_group_name> -d \
  --query '[].{Name:name,Location:location,Power:powerState,Role:tags.role,Env:tags.environment}' \
  --output table
```

Azure's single ANDed include filter makes a partial match invisible in a
different way from the other two: one wrong tag or the wrong location and
*every* host disappears at once, rather than some subset surviving. If the
graph is empty but `az vm list` shows the VMs, compare `location` and the
`application`/`environment` tags in that output against the project
configuration before looking anywhere else.
