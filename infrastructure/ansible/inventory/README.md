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

`internal_ip` is optional in the generic VM contract. Terraform requires it
for effective GCP VMs to preserve existing deterministic addressing. AWS uses
the configured address when present and otherwise lets EC2 assign one; omit it
for an AWS UI because that VM is placed in the public management subnet. The
inventory always exposes the private address actually discovered from the
provider.

## SSH and bastions

Set `OILSCOPE_SSH_USER` when the remote username differs from the controller
username. Use Ansible's standard `ANSIBLE_PRIVATE_KEY_FILE`, SSH agent, or
normal `~/.ssh` configuration for keys; there is no provider-specific key-path
default.

Workloads use their private address through the configured bastion. The
bastion starts on port 22, and the bootstrap play changes it to the configured
`vms.bastion.ssh_port`. For bootstrap, temporarily enable Terraform's
`enable_bastion_ssh_bootstrap` and set `OILSCOPE_BASTION_CONNECT_PORT=22`;
remove both overrides afterward.

## Cross-cloud limitation

Discovery does not create connectivity. A GCP bastion cannot reach an AWS
private subnet, nor can an AWS UI reach private GCP services, without a VPN,
transit design, or authenticated overlay. Private workloads are deliberately
not exposed publicly as a workaround. Keep communicating workloads in one
cloud until cross-cloud private networking is added.

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
