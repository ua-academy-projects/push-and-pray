# Multi-cloud dynamic inventory

`oilscope.yml` uses `oilscope.platform.oilscope`, which reads the same project
configuration as Terraform. It resolves `default_cloud`, per-VM `cloud`, and
logical `region` values, then delegates live discovery only to providers that
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

`default_cloud` and an optional per-VM `cloud` select the provider. `clouds`
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

Workloads in the bastion's cloud use their private address through that
bastion. A public UI in the other cloud is managed directly; Terraform opens
its SSH port only to the bastion's operator CIDRs. This direct management path
does not provide connectivity from the UI to private application services.
The bastion starts on port 22, and the bootstrap play changes it to the
configured `vms.bastion.ssh_port`. For bootstrap, temporarily enable Terraform's
`enable_bastion_ssh_bootstrap` and set `OILSCOPE_BASTION_CONNECT_PORT=22`;
remove both overrides afterward.

## Cross-cloud limitation

Terraform provider dispatch and inventory discovery support GCP-only,
AWS-only, and hybrid configurations. Application deployment supports only a
topology where all five roles are in one cloud. In a hybrid configuration the
inventory publishes `oilscope_application_topology_supported=false` and a
specific error; every workload play checks it on the controller before fact
gathering or SSH. An impossible private cross-cloud SSH proxy also exits with
an explicit error instead of waiting for a timeout.

A GCP bastion cannot reach an AWS private subnet, and workloads in different
clouds cannot use each other's private service addresses, without a VPN,
transit design, or authenticated overlay. Private workloads are deliberately
not exposed publicly as a workaround. Keep all communicating application
roles in one cloud until cross-cloud private networking is added.

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
