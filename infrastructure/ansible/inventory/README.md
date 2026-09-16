# Multi-cloud dynamic inventory

`oilscope.yml` builds one Ansible inventory from live GCP Compute Engine and
AWS EC2 state. Terraform and Ansible read the same project configuration JSON;
provider-specific values are not repeated in the inventory file.

The inventory is recomputed when Ansible runs. It discovers only running
instances whose managed label/tag values match all three values:

- `application=<name_prefix>`
- `environment=<environment>`
- `cloud=gcp` or `cloud=aws`

## Data flow

The `oilscope.platform.oilscope_cloud` wrapper discovers both supported clouds
for compatibility, but it is now multi-cloud. It performs these steps:

1. Read `default_cloud`, `vms`, `regions`, `clouds`, `name_prefix`, and
   `environment` from the shared JSON.
2. Resolve every VM's effective cloud as `vm.cloud` when present, otherwise
   `default_cloud`.
3. Collect the GCP zones and AWS regions used by the selected VMs.
4. Skip a provider entirely when zero configured VMs select it.
5. Delegate live discovery to `google.cloud.gcp_compute` and/or
   `amazon.aws.aws_ec2`.
6. Normalize both provider results into the same host variables and role
   groups.

For example, with `default_cloud: gcp` and `vms.bastion.cloud: aws`, the GCP
delegate queries the zones used by the workload VMs and the AWS delegate
queries the regions used by the bastion. A configuration containing only AWS
VMs never calls the GCP delegate.

## Controller setup

Install both Ansible collections and their Python SDK dependencies:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

Build and install this repository's collection after changing a plugin or
role, because Ansible reads the installed collection rather than the source
file:

```sh
cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
```

For GCP discovery, configure Application Default Credentials:

```sh
gcloud auth application-default login
```

For AWS discovery, use the normal AWS/boto3 credential chain. The Terraform
profile can be selected for the same shell:

```sh
export AWS_PROFILE=terraform
aws sts get-caller-identity
```

Only the credentials for providers selected by at least one configured VM are
needed for that inventory run.

## Selecting the project configuration

The path is resolved in this order:

1. plugin default: `../../terraform/env/dev.json`;
2. `OILSCOPE_PROJECT_CONFIG` environment variable;
3. `project_config_path` written directly in an inventory YAML file.

Use an environment variable for a personal configuration:

```sh
export OILSCOPE_PROJECT_CONFIG=/absolute/path/project-config.json
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.yml \
  --graph
```

An absolute path is used unchanged. A relative path is tried from the current
working directory and then relative to the inventory file.

## Groups and normalized host variables

Both delegates create groups from the provider `role` label/tag:

- `bastion`
- `database`
- `history`
- `fetcher`
- `ui`
- `workloads` for every role except `bastion`

Both providers expose the same normalized variables:

- `internal_ip`
- `public_ip`
- `ansible_host`
- `ansible_port`
- `oilscope_role`
- `oilscope_cloud`

The inventory plugin returns the complete SSH connection data. The bastion uses
its public address and `vms.bastion.ssh_port`; workloads use their private
addresses on port 22 through a generated SSH `ProxyCommand`. It also reads
`OILSCOPE_SSH_USER`, `OILSCOPE_SSH_KEY`, and, only during bootstrap,
`OILSCOPE_BASTION_CONNECT_PORT`. Therefore no `group_vars` files are needed to
re-read configuration JSON, look up another host, or assemble SSH arguments.
Raw GCP fields retain the `gcp_` prefix; AWS provider fields remain available
under the names exposed by `amazon.aws.aws_ec2`.

## SSH host keys in development

`ansible.cfg` disables SSH host-key checking for this project. Development VMs
are routinely recreated at the same address, so their SSH host fingerprints
change by design. The setting applies both to Ansible's direct SSH connection
and to the nested SSH command used by the workload `ProxyCommand`; it is not a
property of an inventory group or of the bastion itself.

Do not use this policy for production infrastructure. There, retain host-key
checking and update `known_hosts` through a controlled process after replacing a
VM.

Hosts appear only after `terraform apply`, because this inventory reports live
cloud resources rather than the desired JSON entries.

## Bastion bootstrap

A new bastion configures `sshd` for `vms.bastion.ssh_port` through its Terraform
startup configuration. Terraform opens only that port to
`vms.bastion.allowed_cidrs`; port 22 is not publicly reachable. Connect using
the configured port after `terraform apply`.

`enable_bastion_ssh_bootstrap` and the `bootstrap_bastion` playbook are retained
only to migrate bastions created before this behavior existed. For such an
existing bastion, enable the temporary ingress rule, run the playbook through
port 22, then apply again without the flag:

```sh
terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path=/absolute/path/project-config.json \
  -var=enable_bastion_ssh_bootstrap=true

export OILSCOPE_BASTION_CONNECT_PORT=22
ansible-playbook oilscope.platform.bootstrap_bastion \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
unset OILSCOPE_BASTION_CONNECT_PORT

terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path=/absolute/path/project-config.json
```

Set `OILSCOPE_SSH_KEY` to the private key matching the public key stored in
`ssh_users`. Never put the private key in JSON, Git, or Terraform state.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `unknown plugin 'oilscope.platform.oilscope_cloud'` | Rebuild and reinstall this repository's collection. |
| `unknown plugin 'google.cloud.gcp_compute'` | Install `google.cloud` from `requirements.yml`. |
| `unknown plugin 'amazon.aws.aws_ec2'` | Install `amazon.aws` from `requirements.yml`. |
| Missing Google library | Install `requirements.txt` and configure ADC. |
| Missing boto3/botocore | Install `requirements.txt`. |
| AWS authentication error | Export the correct `AWS_PROFILE` and verify `aws sts get-caller-identity`. |
| Empty inventory | Confirm that instances are running and their application/environment/cloud labels match the JSON. |

Check provider state directly when inventory is unexpectedly empty:

```sh
gcloud compute instances list --format='table(name,zone,labels)'
aws ec2 describe-instances \
  --filters Name=tag:cloud,Values=aws Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[Tags,PrivateIpAddress,PublicIpAddress]'
```
