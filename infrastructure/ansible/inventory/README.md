# Inventory

`oilscope.yml` builds the deployment inventory from live cloud state across
every provider the project configuration uses, so a `terraform apply` that
replaces a VM or changes an address is picked up without editing a host list.

Every environment-specific value is derived from the project configuration
JSON that Terraform also reads, so this file is identical for every
environment — point `project_config_path` at a different configuration and it
describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

`oilscope.platform.oilscope_cloud` talks to no cloud itself. It reads the
project configuration, works out which clouds actually host workloads, derives
the settings below for each of them, and hands each set to the discovery plugin
that speaks to that provider:

| Cloud | Discovery plugin | Collection |
| --- | --- | --- |
| `gcp` | `google.cloud.gcp_compute` | `google.cloud` |
| `aws` | `amazon.aws.aws_ec2` | `amazon.aws` |

Hosts from every cloud land in one inventory, in the same role groups.

The wrapper exists because neither discovery plugin can read the project
configuration, and neither evaluates Jinja in its own configuration file — a
template expression placed there is sent to the API as literal text.

| Derived from the JSON | Becomes on GCP | Becomes on AWS |
| --- | --- | --- |
| `clouds.<cloud>.project_id` | the project queried | — |
| `clouds.<cloud>.zone` | the zone queried | — |
| `clouds.<cloud>.region` | — | the region queried |
| `name_prefix` | `labels.application` filter | `tag:application` filter |
| `environment` | `labels.environment` filter | `tag:environment` filter |
| the cloud's own name | `labels.cloud` filter | `tag:cloud` filter |
| `ssh_port` of that cloud's bastion | that bastion's `ansible_port` | same |

## Which clouds are queried

A cloud is queried only when it hosts at least one workload. This mirrors the
Terraform modules: a cloud whose only VM is a bastion is never built, because a
bastion with nothing to reach serves no purpose, so there is nothing to
discover either.

Each cloud must own exactly one bastion. The plugin refuses a configuration
where a cloud with workloads has none or has two.

## Crossing clouds is not possible

Every host gets `oilscope_cloud` from its own `cloud` label or tag, and
`group_vars/workloads.yml` uses it to pick the bastion of that same cloud.
Routing a GCP host through an AWS bastion would produce an SSH timeout rather
than an error, so the selection is explicit rather than "the first bastion in
the group".

Everything else — the grouping rules, the host-variable expressions, the
workload SSH port — lives in the plugin's defaults. Changing those means
editing the plugin and rebuilding the collection, not editing this directory.

## Setup

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

This repository's own collection must also be installed, because there is no
`ansible.cfg` pointing Ansible at the working copy:

```sh
cd infrastructure/ansible/oilscope/platform && ansible-galaxy collection build --force && ansible-galaxy collection install oilscope-platform-*.tar.gz --force
```

Repeat that after every change to the plugin or to a role — Ansible reads the
installed copy, not the files you just edited.

## Pointing it at your configuration

`oilscope.yml` carries no path of its own, because the project configuration
does not live in the same place for everyone. The path is resolved in three
steps, weakest first:

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
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json \
  --graph
```

Hosts appear only after `terraform apply`: the inventory reports what exists in
GCP, so before the infrastructure is created it is legitimately empty.

## Groups

Terraform labels every VM with `role=<role>`, which becomes the `bastion`,
`database`, `history`, `fetcher` and `ui` groups the deployment roles expect.
Everything except the bastion also joins `workloads`.

The group name comes from the `role` label, not from the key in the project
configuration: `vms.infra` has `role: database` and therefore lands in the
`database` group, which is what the `ui` role looks for.

## Host variables

`internal_ip` is set on every host. This is a contract, not a convenience: the
`ui` role resolves its Database and History peers through that exact variable
name. Also set: `public_ip`, `oilscope_role`, `ansible_host`, `ansible_port`.
For the bastion, `bastion_ssh_port` is always the final port from
`vms.bastion.ssh_port`. `ansible_port` normally uses that value, but can use
`OILSCOPE_BASTION_CONNECT_PORT` during the one-time bootstrap connection.

Raw instance fields from the API are prefixed with `gcp_`, because two of them
— `name` and `tags` — collide with names Ansible reserves.

## SSH

The bastion is normally reached on its external address at the final port read
from `vms.bastion.ssh_port` in the project config by
`group_vars/bastion.yml`. Every workload is reached on its internal address at
port 22, through a `ProxyCommand` defined in `group_vars/workloads.yml`. The
ProxyCommand always uses the bastion's final port; the bootstrap connection
override applies only to the bastion itself. Pass the absolute project config
path on every inventory, ad-hoc and playbook command.

The non-default port belongs to the bastion alone; applying it globally would
break every workload connection.

Terraform does not configure `sshd`. A newly created bastion therefore starts
on port 22, and Ansible changes it to the final configured port. Use this
bootstrap sequence whenever the bastion has not yet been configured.

1. Apply Terraform with the temporary port-22 rule enabled. The rule is
   restricted to `vms.bastion.allowed_cidrs`, targets only the bastion, and is
   not created when the final port is already 22.

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
ansible-playbook oilscope.platform.bootstrap_bastion \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json
unset OILSCOPE_BASTION_CONNECT_PORT
```

3. Confirm a new Ansible connection works on the final configured port.

```sh
ansible bastion \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -m ansible.builtin.ping
```

4. Apply Terraform again without the bootstrap variable. Its default is
   `false`, so Terraform removes the temporary port-22 rule without changing
   any VM.

```sh
terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path=/absolute/path/project-config.json
```

5. Confirm the temporary firewall rule no longer exists and port 22 is not
   reachable from an allowed operator address. The exact rule name ends in
   `-allow-bastion-ssh-bootstrap`.

```sh
gcloud compute firewall-rules list \
  --filter='name~allow-bastion-ssh-bootstrap' \
  --format='value(name)'
```

The command must return no rule. Workload playbooks do not use the bootstrap
override; their existing ProxyCommand connects to the bastion through the
final configured port and then reaches workload SSH on port 22.

`ansible_user` (in `group_vars/all.yml`) defaults to the controller's own login
name, because that is the name a key added through `gcloud compute ssh` is
registered under in GCP project metadata. Everyone connects as themselves and
no name is committed. Override for one run with `OILSCOPE_SSH_USER`, and the
key with `OILSCOPE_SSH_KEY`.

## When it looks broken

| Symptom | Cause |
| --- | --- |
| `No inventory was parsed`, doubled path in the message | not run from the repository root |
| `unknown plugin 'oilscope.platform.oilscope_cloud'` | this repository's collection is not installed, or was not rebuilt |
| `unknown plugin 'google.cloud.gcp_compute'` | `requirements.yml` not installed |
| `cannot start: ... library (google-auth)` | `requirements.txt` not installed |
| `must define a 'vms' object` | the JSON is still `config_version` 2 |
| **Empty `@all`, exit status 0** | `project_id`, `zone` or the labels do not match reality |
| `Permission denied (publickey)` | the account is absent from `ssh_users`, or the wrong key |

The empty-inventory case is the dangerous one: the delegate swallows API
errors, so a wrong project or zone looks exactly like a working inventory with
nothing in it. Check against GCP directly rather than trusting the graph:

```sh
gcloud compute instances list --format="table(name,zone,labels)"
```
