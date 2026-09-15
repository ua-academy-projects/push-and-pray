# Multi-cloud dynamic inventory

`oilscope.yml` uses `oilscope.platform.oilscope`, which reads the same project
configuration as Terraform. It resolves `default_cloud` and logical `region` values,
then delegates live discovery only to the provider used by the deployment:
are actually used:

- `google.cloud.gcp_compute` discovers GCP instances by `application`,
  `environment`, and `cloud=gcp` labels.
- `amazon.aws.aws_ec2` discovers AWS instances by the equivalent tags.

Both delegates expose the provider-neutral `bastion`, `database`, `history`,
`fetcher`, `ui`, and `workloads` groups. The `infra` VM is grouped as
`database` because grouping uses its `role`, not its configuration key. Hosts
also expose `internal_ip`, `public_ip`, `oilscope_role`, `oilscope_cloud`,
`oilscope_region`, `ansible_host`, and `ansible_port`.

## Setup

Ubuntu's system Python is externally managed, so use an isolated controller
environment rather than installing into it directly:

```sh
uv venv .venv
uv pip install --python .venv/bin/python \
  ansible ansible-lint \
  -r infrastructure/ansible/requirements.txt
source .venv/bin/activate
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
```

GCP uses Application Default Credentials. AWS uses the normal boto3 credential
chain. Configure only credentials for clouds present in the project config.

From the repository root, point the inventory at a config with an absolute
path or `OILSCOPE_PROJECT_CONFIG`:

```sh
OILSCOPE_PROJECT_CONFIG=/absolute/path/project-config.json \
  ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph
```

The default is the repository's `project-config.example.json`. Inventory is
live, so it is empty until matching instances exist.

The generic VM contract does not accept a static `internal_ip`. Each provider
assigns an address from the subnet selected for the VM role, Terraform outputs
the assigned address, and inventory exposes the private address discovered
from the provider as `internal_ip`. Existing GCP instances keep their current
address while they exist; a replacement can receive a different address.

`default_cloud` selects the provider for all five roles. `clouds`
declares which providers may be used; `cloud_mappings` translates logical
region, size, disk, and image names. Terraform hard-fails when an effective
provider is undeclared, a mapping is missing, one provider resolves to more
than one region or zone, required application roles are duplicated or absent,
or network CIDRs violate provider limits. `application`, `environment`,
`managed_by`, `role`, `cloud`, and AWS `Name` are managed identity labels/tags
and cannot be supplied through user metadata.

## SSH and bastions

Set `OILSCOPE_SSH_USER` when the remote username differs from the controller
username. Use Ansible's standard `ANSIBLE_PRIVATE_KEY_FILE`, SSH agent, or
normal `~/.ssh` configuration for keys; there is no provider-specific key-path
default.

Workloads use their private address through the bastion, including the public
UI. The nested ProxyCommand explicitly passes `ANSIBLE_PRIVATE_KEY_FILE` when
set. Bastion first-boot logic configures `vms.bastion.ssh_port` (8787 in the
example); Ansible waits for that port and enforces the same SSH policy.
No temporary public port 22 or bootstrap connection override is needed.
The inventory plugin propagates the absolute project-config path as a host
variable, so deployment roles consume the same file used for discovery.

## Cross-cloud limitation

One configuration selects one cloud. Terraform rejects a VM `cloud` override that does
not match `default_cloud`, and the `topology_guard` repeats the invariant against live
inventory before gathering facts or opening workload SSH connections. Cross-cloud private
application networking and multiple bastions are outside scope.

AWS private-subnet internet egress is disabled by default. Setting
`network.aws_enable_nat_gateway` to `true` creates a paid NAT Gateway; review
AWS pricing before enabling it. Current Ansible deployment of private AWS
workloads needs outbound access for apt package installation, GHCR image pulls,
and AWS Secrets Manager API calls. Set the flag to `true` unless the VPC has an
alternative egress path or suitable private endpoints and package mirrors.

## Troubleshooting

- Rebuild and reinstall `oilscope.platform` after editing its plugin.
- Install both collections and Python requirements if a delegate is unknown.
- Verify project, mappings, credentials, and identity labels/tags when empty.
- Ensure every operator username and public key exists in `ssh_users`.
