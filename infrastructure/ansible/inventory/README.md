# Inventory

The `oilscope.gcp.yml`, `oilscope.aws.yml`, and `oilscope.azure.yml` sources
build the deployment inventory from live cloud state, so a `terraform apply`
that replaces a VM or changes an address is picked up without editing a host
list.

Every environment-specific value is derived from the project configuration
JSON that Terraform also reads, so this file is identical for every
environment — point `project_config_path` at a different configuration and it
describes a different environment.

The inventory is dynamic in the Ansible sense: recomputed on every run. Nothing
polls in the background; `cache_timeout` only bounds how long a previous API
response is reused.

## How it fits together

The local inventory plugins do not call cloud APIs themselves. They read the
project configuration and delegate discovery to `google.cloud.gcp_compute`,
`amazon.aws.aws_ec2`, or `azure.azcollection.azure_rm`.

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
editing the local plugin, not editing the inventory source.

## Setup

All three steps are required, and skipping one produces a failure that does not
name the missing piece:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt
gcloud auth application-default login
az login
```

`requirements.yml` installs all three cloud collections. `requirements.txt`
installs the direct controller libraries. Azure keeps its larger SDK set in
the collection-level requirements file, which is why it has a separate pip
command. `ansible-galaxy` installs collections, never their Python packages.

## Pointing it at your configuration

The committed inventory sources carry no configuration path because it does
not live in the same place for everyone. Set `OILSCOPE_PROJECT_CONFIG`, or add
`project_config_path` to a private inventory source. A value in the source
takes precedence over the environment variable.

So a configuration kept elsewhere needs no edit to a committed file:

```sh
OILSCOPE_PROJECT_CONFIG=.venv/bootstrap_gcp/project-config.json \
  ansible-inventory -i infrastructure/ansible/inventory/oilscope.azure.yml --graph
```

Export it once and every later command picks it up. An absolute path is used as
given; a relative one is tried against the working directory first, then
against this directory, so a path typed from the repository root works.

An absolute path is used as given. A relative path is tried against the current
working directory first and then relative to the selected inventory source.

## Usage

After Terraform apply, export its non-secret service endpoints for the
workload playbooks:

```sh
terraform -chdir=infrastructure/terraform output -json service_endpoints \
  > .venv/oilscope-service-endpoints.json
export OILSCOPE_SERVICE_ENDPOINTS="$(realpath .venv/oilscope-service-endpoints.json)"
```

The generated file contains database, RabbitMQ and Redis hosts and ports, but
no passwords. Passwords continue to come from the cloud secret manager.

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
`infra`, `history`, `fetcher` and `ui` groups the deployment roles expect.
Everything except the bastion also joins `workloads`.

The group name comes from the `role` label, not from the key in the project
configuration: `vms.infra` has `role: infra` and hosts RabbitMQ and Redis.
Managed database connection data comes from Terraform's `service_endpoints`
output rather than from an inventory host.

## Host variables

`internal_ip` is set on every host. The UI role resolves History through this
variable; managed service endpoints come from the Terraform output file. Also
set: `public_ip`, `oilscope_role`, `oilscope_cloud`, `ansible_host`,
`ansible_port`.
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
ansible-playbook \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  infrastructure/ansible/playbooks/bootstrap_bastion.yml
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
| `unknown plugin 'oilscope_gcp'` | `ANSIBLE_CONFIG` does not point to `infrastructure/ansible/ansible.cfg` |
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
