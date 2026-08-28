# Inventory

`oilscope.yml` builds the deployment inventory from live Compute Engine state,
so a `terraform apply` that replaces a VM or changes an address is picked up
without editing a host list.

Every environment-specific value is derived from the project configuration
JSON that Terraform also reads, so this file is identical for every
environment — point `project_config_path` at a different configuration and it
describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

`oilscope.platform.oilscope_gcp` does not talk to GCP itself. It reads the
project configuration, derives the settings below, and hands them to
`google.cloud.gcp_compute`, which performs the discovery.

The wrapper exists because `gcp_compute` can neither read the project
configuration nor evaluate Jinja in its own configuration file — a template
expression placed there is sent to the API as literal text.

| Derived from the JSON | Becomes |
| --- | --- |
| `project_id` | the project queried |
| `zone` | the zone queried |
| `name_prefix` | the `labels.application` filter |
| `environment` | the `labels.environment` filter |
| `ssh_port` of the VM whose `role` is `bastion` | the bastion's `ansible_port` |

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

## Usage

```sh
ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph
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

Raw instance fields from the API are prefixed with `gcp_`, because two of them
— `name` and `tags` — collide with names Ansible reserves.

## SSH

The bastion is reached on its external address at the port from the project
configuration. Workloads are reached on their internal address at port 22 —
the only port the Terraform workload firewall rule opens — through a
`ProxyCommand` defined in `group_vars/workloads.yml`.

The non-default port belongs to the bastion alone; applying it globally would
break every workload connection.

`ansible_user` (`group_vars/all.yml`) defaults to the controller's own login
name, because that is the name a key added through `gcloud compute ssh` is
registered under in GCP project metadata. Everyone connects as themselves and
no name is committed. Override for one run with `OILSCOPE_SSH_USER`, and the
key with `OILSCOPE_SSH_KEY`.

## When it looks broken

| Symptom | Cause |
| --- | --- |
| `No inventory was parsed`, doubled path in the message | not run from the repository root |
| `unknown plugin 'oilscope.platform.oilscope_gcp'` | this repository's collection is not installed, or was not rebuilt |
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
