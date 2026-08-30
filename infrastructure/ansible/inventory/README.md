# Inventory

`oilscope.gcp.yml` builds the deployment inventory from live Compute Engine
state using the upstream `google.cloud.gcp_compute` plugin, so a
`terraform apply` that replaces a VM or changes an address is picked up without
editing a host list.

It is dynamic in the Ansible sense — recomputed on every run. Nothing polls in
the background; `cache_timeout` only bounds how long a previous API response is
reused.

## Setup

All three steps are required. None of them is optional, and skipping one
produces a failure that does not name the missing piece:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
gcloud auth application-default login
```

`requirements.yml` installs the `google.cloud` collection, which provides the
`gcp_compute` plugin itself. `requirements.txt` installs the Python libraries
that plugin imports at run time — `google-auth` and `requests`.

The two are separate on purpose: `ansible-galaxy` installs collections, never
Python packages. The collection does ship its own `requirements.txt` naming the
same libraries, but nothing ever executes it — installing them is the caller's
job.

Both failures look like an inventory that simply does not exist, so they are
worth recognising. Without the collection:

```
[WARNING]: Failed to parse inventory with 'auto' plugin: inventory config
'.../oilscope.gcp.yml' specifies unknown plugin 'google.cloud.gcp_compute'
```

With the collection but without the Python libraries — the plugin refuses
before reading a single option:

```
[WARNING]: Failed to parse inventory with 'auto' plugin: gce inventory plugin
cannot start: Failed to import the required Python library (google-auth) on
<host>'s Python <interpreter>.
```

In both cases Ansible then reports "No inventory was parsed, only implicit
localhost is available" and every play matches nothing.

Then edit `projects`, `zones` and the `filters` labels in `oilscope.gcp.yml` to
match the project configuration JSON for the environment being deployed. The
plugin cannot read that JSON, and Jinja is not evaluated in this file, so those
values cannot be derived automatically. Keeping one copy of the file per
environment is the usual way to avoid editing it before each run.

## Usage

```sh
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json \
  --graph
```

A misconfigured `projects` or `filters` value produces an **empty inventory and
exit status 0**, not an error — the plugin swallows the API failure. If a
playbook reports "no hosts matched", check the inventory with the command above
before looking anywhere else.

## Groups

Terraform labels every VM with `role=<role>`, which `keyed_groups` turns into
the `bastion`, `database`, `history`, `fetcher` and `ui` groups the deployment
roles expect. Everything except the bastion also joins `workloads`.

Note that the group name comes from the `role` label, not from the key in the
project configuration JSON: `vms.infra` has `role: database` and therefore
lands in the `database` group, which is what the `ui` role looks for.

## Host variables

`internal_ip` is set on every host. This is a contract, not a convenience: the
`ui` role resolves its Database and History peers through that exact variable
name. Also set: `public_ip`, `oilscope_role`, `ansible_host`, `ansible_port`.
For the bastion, `bastion_ssh_port` is always the final port from
`vms.bastion.ssh_port`. `ansible_port` normally uses that value, but can use
`OILSCOPE_BASTION_CONNECT_PORT` during the one-time bootstrap connection.

## SSH

The bastion is normally reached on its external address at the final port read
from `vms.bastion.ssh_port` in the project config by
`group_vars/bastion.yml`. Every workload is reached on its internal address at
port 22, through a `ProxyCommand` defined in `group_vars/workloads.yml`. The
ProxyCommand always uses the bastion's final port; the bootstrap connection
override applies only to the bastion itself. Pass the absolute project config
path on every inventory, ad-hoc and playbook command.

The non-default port belongs to the bastion alone — the Terraform workload
firewall rule opens 22 and nothing else, so applying that port globally would
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
no name is committed. Override for one run with `OILSCOPE_SSH_USER`, or edit
`group_vars/all.yml` to pin a single shared account.
