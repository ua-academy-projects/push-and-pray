# Inventory

`oilscope.yml` builds the deployment inventory from live GCP and AWS state,
so a `terraform apply` that replaces a VM or changes an address is picked up
without editing a host list. Both clouds are always queried; a VM shows up in
whichever one Terraform actually created it on, decided by the `cloud`
label/tag Terraform stamps on every instance.

Every environment-specific value is derived from the project configuration
JSON that Terraform also reads, so this file is identical for every
environment — point `project_config_path` at a different configuration and it
describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

`oilscope.platform.oilscope_compute` does not talk to GCP or AWS itself. It
reads the project configuration, derives the settings below, and hands them
to `google.cloud.gcp_compute` and `amazon.aws.aws_ec2`, which perform the
actual discovery — one delegate call per cloud, merged into one inventory.

The wrapper exists because neither delegate can read the project
configuration nor evaluate Jinja in its own configuration file — a template
expression placed there is sent to the API as literal text.

| Derived from the JSON | Becomes |
| --- | --- |
| `project_id` | the GCP project queried (GCP is skipped entirely if absent) |
| every `zone` in `regions.*.gcp` | the GCP zones queried |
| every `region` in `regions.*.aws` | the AWS regions queried |
| `name_prefix` | the `application` filter on both clouds |
| `environment` | the `environment` filter on both clouds |
| `ssh_port` of the VM whose `role` is `bastion` | the bastion's `ansible_port` |

Both delegates are always invoked (skipping GCP only when `project_id` is
absent from the configuration); which resources they actually find is
decided entirely by the `cloud`/`Cloud` label or tag Terraform stamps on
every instance, not by the plugin re-deriving each VM's `cloud` override in
Python. This keeps the config's `coalesce(vm.cloud, config.cloud)` resolution
a single source of truth, computed once by Terraform, read back by Ansible.

Everything else — the grouping rules, the host-variable expressions, the
workload SSH port — lives in the plugin's defaults. Changing those means
editing the plugin and rebuilding the collection, not editing this directory.

## Setup

All four steps are required, and skipping one produces a failure that does not
name the missing piece:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
gcloud auth application-default login
aws configure
```

`requirements.yml` installs the `google.cloud` and `amazon.aws` collections,
which provide the `gcp_compute` and `aws_ec2` plugins this one delegates to.
`requirements.txt` installs the Python libraries those plugins import at run
time — `google-auth`/`requests` for GCP, `boto3`/`botocore` for AWS.
`ansible-galaxy` installs collections, never Python packages, so neither file
covers for the other.

`aws configure` (or exporting `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, or
an attached IAM role) sets up the standard boto3 credential chain `aws_ec2`
authenticates through — the AWS equivalent of `gcloud auth
application-default login` on the GCP side. Both are required even if your
own environment only uses one cloud today, because the plugin always queries
both.

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

Hosts appear only after `terraform apply`: the inventory reports what exists
on GCP and AWS, so before the infrastructure is created it is legitimately
empty. A VM appears under whichever cloud Terraform actually created it on —
an environment that only uses one cloud simply gets an empty result from the
other's delegate, which is not an error.

## Groups

Terraform labels every VM with `role=<role>` (`Role` tag on AWS) and
`cloud=<cloud>` (`Cloud` tag on AWS), which becomes the `bastion`, `database`,
`history`, `fetcher`, `ui`, `gcp` and `aws` groups. Everything except the
bastion also joins `workloads`, regardless of which cloud it's on.

The role group name comes from the `role` label, not from the key in the
project configuration: `vms.infra` has `role: database` and therefore lands
in the `database` group, which is what the `ui` role looks for.

## Host variables

`internal_ip` is set on every host. This is a contract, not a convenience: the
`ui` role resolves its Database and History peers through that exact variable
name. Also set: `public_ip`, `oilscope_role`, `oilscope_cloud`,
`ansible_host`, `ansible_port`. For the bastion, `bastion_ssh_port` is always
the final port from `vms.bastion.ssh_port`, and `ansible_port` always uses
that same value.

Raw GCP instance fields are prefixed with `gcp_`, because two of them — `name`
and `tags` — collide with names Ansible reserves. Raw AWS instance fields are
not prefixed; `aws_ec2` has no equivalent option, so only the `compose`d
variables above are guaranteed stable across collection versions.

## SSH

The bastion is normally reached on its external address at the final port read
from `vms.bastion.ssh_port` in the project config by
`group_vars/bastion.yml`. Every workload is reached on its internal address at
port 22, through a `ProxyCommand` defined in `group_vars/workloads.yml`, which
always uses the bastion's final port. Pass the absolute project config path on
every inventory, ad-hoc and playbook command.

The non-default port belongs to the bastion alone; applying it globally would
break every workload connection.

Terraform boots a new bastion listening on the final configured port already
— a startup script installs the `sshd` drop-in before the instance ever
accepts connections, so there is no window where it listens on 22 and no
temporary firewall rule to open and close around it. Ansible connects
directly on the final port and re-applies the rest of the `sshd` policy (key
auth only, no root login, and so on):

```sh
ansible-playbook oilscope.platform.bootstrap_bastion \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

This is safe to re-run at any time — for example after changing
`vms.bastion.ssh_port` or `allowed_cidrs` in the project config and
re-applying Terraform — to bring the running bastion back in line with the
policy the role defines.

`ansible_user` (in `group_vars/all.yml`) defaults to the controller's own login
name, because that is the name a key added through `gcloud compute ssh` is
registered under in GCP project metadata. Everyone connects as themselves and
no name is committed. Override for one run with `OILSCOPE_SSH_USER`, and the
key with `OILSCOPE_SSH_KEY`.

## When it looks broken

| Symptom | Cause |
| --- | --- |
| `No inventory was parsed`, doubled path in the message | not run from the repository root |
| `unknown plugin 'oilscope.platform.oilscope_compute'` | this repository's collection is not installed, or was not rebuilt |
| `unknown plugin 'google.cloud.gcp_compute'` | `requirements.yml` not installed |
| `unknown plugin 'amazon.aws.aws_ec2'` | `requirements.yml` not installed |
| `cannot start: ... library (google-auth)` | `requirements.txt` not installed |
| `Unable to locate credentials` | AWS credential chain not set up — run `aws configure` |
| `must define a 'vms' object` | the JSON is still `config_version` 2 |
| **Empty `@all`, exit status 0** | `project_id`, region/zone, or the labels/tags do not match reality |
| `Permission denied (publickey)` | the account is absent from `ssh_users`, or the wrong key |

The empty-inventory case is the dangerous one: both delegates swallow API
errors, so a wrong project, zone, region, or a stale `cloud`/`Cloud` tag looks
exactly like a working inventory with nothing in it. Check against each cloud
directly rather than trusting the graph:

```sh
gcloud compute instances list --format="table(name,zone,labels)"
aws ec2 describe-instances --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,State:State.Name,Tags:Tags}"
```
