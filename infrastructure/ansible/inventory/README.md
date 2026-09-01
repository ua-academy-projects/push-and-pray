# Inventory

`oilscope.yml` builds the deployment inventory from live cloud state, so a
`terraform apply` that replaces a VM or changes an address is picked up without
editing a host list. It covers every cloud the project configuration targets,
so a deployment split between GCP and AWS still produces one inventory.

Every environment-specific value is derived from the project configuration
JSON that Terraform also reads, so this file is identical for every
environment — point `project_config_path` at a different configuration and it
describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

`oilscope.platform.oilscope` does not talk to any cloud itself. It reads the
project configuration, works out which clouds the VMs are in, derives the
settings below, and hands them to the upstream plugin of each cloud —
`google.cloud.gcp_compute` for `gcp` and `amazon.aws.aws_ec2` for `aws`. Both
write into the same inventory, so a mixed deployment produces one host list.

The wrapper exists because neither upstream plugin can read the project
configuration or evaluate Jinja in its own configuration file — a template
expression placed there is sent to the API as literal text.

| Derived from the JSON | Becomes |
| --- | --- |
| `default_cloud`, `vms[*].cloud` | which upstream plugins run |
| `gcp.project_id` | the GCP project queried |
| `aws.regions` | the AWS regions queried |
| `name_prefix` | the `application` label or tag filter |
| `environment` | the `environment` label or tag filter |

The GCP search is not narrowed to a zone: the portable configuration names a
`location` token rather than a zone, and the label filters already scope the
result to one deployment. AWS has no equivalent — `aws_ec2` searches only the
regions it is given, which is why `aws.regions` is required whenever a VM
targets AWS.

`ansible_port` is deliberately **not** among them. Host variables produced by
an inventory plugin outrank the `group_vars/` of the same inventory, so
composing it here would silently disable the bootstrap override in
`group_vars/bastion.yml` — and the bastion is exactly the host that needs it.
The port therefore stays where the override lives.

Everything else — the grouping rules, the host-variable expressions — lives in
the plugin's defaults. Changing those means
editing the plugin and rebuilding the collection, not editing this directory.

## Setup

All three steps are required, and skipping one produces a failure that does not
name the missing piece:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
gcloud auth application-default login
```

`requirements.yml` installs the `google.cloud` and `amazon.aws` collections,
which provide the `gcp_compute` and `aws_ec2` plugins this one delegates to.
`requirements.txt` installs the Python libraries those plugins import at run
time — `google-auth` and `requests` for GCP, `boto3` and `botocore` for AWS.
`ansible-galaxy` installs collections, never Python packages, so neither file
covers for the other.

The last step authenticates GCP. A configuration with VMs in AWS needs AWS
credentials the CLI would already accept — an environment, a profile or an
instance role — and nothing else; the plugin sets no credentials of its own.
A GCP-only configuration never reaches the AWS plugin, and the reverse.

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
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json \
  --graph
```

Hosts appear only after `terraform apply`: the inventory reports what exists in
the cloud, so before the infrastructure is created it is legitimately empty.

## Groups

Terraform labels every VM with `role=<role>` — a Compute Engine label on GCP,
an instance tag on AWS — which becomes the `bastion`, `database`, `history`,
`fetcher` and `ui` groups the deployment roles expect. Everything except the
bastion also joins `workloads`, and every host joins `cloud_gcp` or `cloud_aws`
by the provider it was discovered in.

The group name comes from the `role` label, not from the key in the project
configuration: `vms.infra` has `role: database` and therefore lands in the
`database` group, which is what the `ui` role looks for.

## Host variables

`internal_ip` is set on every host. This is a contract, not a convenience: the
`ui` role resolves its Database and History peers through that exact variable
name. Also set: `public_ip`, `oilscope_role`, `oilscope_cloud`, `ansible_host`,
`ansible_port`. `oilscope_cloud` is what the `resolve_secrets` role branches on
to reach Secret Manager or Secrets Manager.
For the bastion, `bastion_ssh_port` is always the final port from
`vms.bastion.ssh_port`. `ansible_port` normally uses that value, but can use
`OILSCOPE_BASTION_CONNECT_PORT` during the one-time bootstrap connection.

Raw instance fields are prefixed — `gcp_` on GCP, `aws_` on AWS — because
`name` and `tags` collide with names Ansible reserves. `aws_ec2` spells that
option `hostvars_prefix`, and the prefix reaches the group expressions too, so
every AWS rule reads `aws_tags` first and falls back to `ec2_tags` and then to
`tags`. That covers a run without the prefix and the upstream rename of `tags`
to `ec2_tags` alike.

The AWS settings also set `strict: true`. Without it a group expression that
fails to evaluate is skipped in silence: the host still appears, the group
simply never exists, and what breaks is whatever depended on that group — the
bastion's port override, the workloads' `ProxyCommand` — far from the cause.

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
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
unset OILSCOPE_BASTION_CONNECT_PORT
```

3. Confirm a new Ansible connection works on the final configured port.

```sh
ansible bastion \
  -i infrastructure/ansible/inventory/oilscope.yml \
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
key with `OILSCOPE_SSH_KEY`. The key default, `~/.ssh/google_compute_engine`,
is a GCP artefact; on AWS, where the accounts come from `ssh_users` in the
project configuration rather than from project metadata, set
`OILSCOPE_SSH_KEY`.

## When it looks broken

| Symptom | Cause |
| --- | --- |
| `No inventory was parsed`, doubled path in the message | not run from the repository root |
| `unknown plugin 'oilscope.platform.oilscope'` | this repository's collection is not installed, or was not rebuilt |
| `the google.cloud.gcp_compute inventory plugin is unavailable` | `requirements.yml` not installed |
| `the amazon.aws.aws_ec2 inventory plugin is unavailable` | `requirements.yml` not installed |
| `cannot start: ... library (google-auth)` | `requirements.txt` not installed |
| `must define a non-empty aws.regions list` | a VM targets AWS and the configuration names no region |
| `names no cloud and the configuration defines no ... 'default_cloud'` | the JSON predates the portable schema |
| `must define a 'vms' object` | the JSON is still `config_version` 2 |
| **Empty `@all`, exit status 0** | `gcp.project_id`, `aws.regions` or the labels do not match reality |
| `Permission denied (publickey)` | the account is absent from `ssh_users`, or the wrong key |

The empty-inventory case is the dangerous one: the delegates swallow API
errors, so a wrong project or region looks exactly like a working inventory
with nothing in it. Check against the provider directly rather than trusting
the graph:

```sh
gcloud compute instances list --format="table(name,zone,labels)"
aws ec2 describe-instances --region <region> \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table
```
