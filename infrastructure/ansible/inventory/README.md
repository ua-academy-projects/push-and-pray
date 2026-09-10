# Cloud inventory

`oilscope.yml` discovers the live virtual machines described by the same
`project-config.json` that Terraform reads. The inventory source is independent
of the selected environment and of whether its VMs use GCP, AWS, or both.

The inventory is dynamic in the Ansible sense: it is rebuilt when an Ansible
command loads it. It does not poll in the background.

## How discovery works

`oilscope.platform.oilscope_cloud` reads the project configuration and resolves
the effective `cloud` and `location` of every VM from its explicit values or
the top-level defaults. It then:

- queries `google.cloud.gcp_compute` for the GCP projects and zones in use;
- queries `amazon.aws.aws_ec2` for the AWS regions in use;
- skips a provider when no configured VM uses it;
- keeps only live instances whose Terraform resource names match configured
  VMs;
- creates functional inventory groups from each VM's `tags` array.

The JSON configuration remains the authority for logical placement and
grouping. Cloud APIs provide live existence and current public addresses.

## Setup

Install Ansible with pipx, add the provider Python libraries to the same pipx
environment, and install the provider collections:

```sh
pipx install ansible-core
pipx runpip ansible-core install \
  -r infrastructure/ansible/requirements.txt

ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

Build and install this repository's collection:

```sh
cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
cd ../../../..
```

Repeat the collection build and installation after changing the plugin or a
role. Ansible loads the installed collection rather than this working tree.

For GCP, create Application Default Credentials:

```sh
gcloud auth application-default login
```

For AWS, use the normal AWS credential chain. To select a named profile:

```sh
export AWS_PROFILE=your-aws-profile
```

Both credentials must be available when the current configuration contains VMs
in both clouds. Only the credential for the selected cloud is needed when all
VMs use one provider.

## Select the project configuration

The plugin uses `project-config.json` from the current directory by default.
Select another file with an environment variable:

```sh
export OILSCOPE_PROJECT_CONFIG=/absolute/path/project-config.json
```

## Inspect the inventory

Run from the repository root:

```sh
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.yml \
  --graph

ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.yml \
  --list
```

Hosts appear only after `terraform apply`. A mixed-cloud test should show both
the `aws` and `gcp` groups. Functional tags create groups such as `bastion`,
`database`, `history`, `fetcher`, and `ui`; every non-bastion also joins
`workloads`.

## Normalized host variables

Every discovered host receives:

| Variable | Meaning |
| --- | --- |
| `internal_ip` | address from the VM's JSON configuration |
| `public_ip` | current address discovered from the provider |
| `oilscope_cloud` | `aws` or `gcp` |
| `oilscope_location` | logical location key from the configuration |
| `oilscope_tags` | functional tags from the VM definition |
| `oilscope_vm_name` | VM key from the `vms` object |

For a bastion, `ansible_host` is its public address and both `ansible_port` and
`bastion_ssh_port` come from its VM definition. Other VMs use their internal
address and port 22.

## SSH routing

The `aws` group connects as `ubuntu`, matching the configured Ubuntu AMIs. The
`gcp` group uses the controller's `$USER`, matching the usernames in GCP SSH
metadata. Override either default with `OILSCOPE_SSH_USER`.

Set `OILSCOPE_SSH_KEY` when the private key is not one of OpenSSH's default
identities or available through `ssh-agent`. The same optional key is used for
the controller-to-bastion and bastion-to-workload connections:

```sh
export OILSCOPE_SSH_KEY="$HOME/.ssh/google_compute_engine"
```

Workload connections use the host in the `bastion` group as an SSH proxy.
Terraform supplies cloud-init user data that configures the bastion's custom
SSH port during its first boot, and the cloud firewall permits only that port.
No separate bastion bootstrap playbook or temporary port override is required.

Inventory discovery does not provide cross-cloud routing. For application
deployment, the bastion and its private workloads must be mutually reachable.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `unknown plugin 'oilscope.platform.oilscope_cloud'` | rebuild and reinstall this repository's collection |
| `unknown plugin 'google.cloud.gcp_compute'` | install `requirements.yml` |
| `unknown plugin 'amazon.aws.aws_ec2'` | install `requirements.yml` |
| missing `google-auth`, `boto3`, `botocore`, or `awscrt` | install `requirements.txt` with `pipx runpip ansible-core` |
| the `aws` group is empty | verify `aws sts get-caller-identity` with the selected profile |
| the `gcp` group is empty | verify the active ADC account and configured project |
| a configured host is absent | confirm Terraform created it with the expected `<prefix>-<environment>-<VM key>` name |

Use `-vvv` to see which configured VM names were not returned by a provider.
