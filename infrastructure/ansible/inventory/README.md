# Cloud inventory

`oilscope.yml` discovers the live virtual machines described by the same
`project-config.json` that Terraform reads. The top-level `bastion` object and
the workload machines in `vms` are normalized into one inventory. The inventory source is independent of the selected environment and of whether
its VMs use AWS, Azure, GCP, or a combination of them.

The inventory is dynamic in the Ansible sense: it is rebuilt when an Ansible
command loads it. It does not poll in the background.

## How discovery works

`oilscope.platform.oilscope_cloud` reads the project configuration and resolves
the effective `cloud` and `location` of every VM from its explicit values or
the top-level defaults. It then:

- queries `google.cloud.gcp_compute` for the GCP projects and zones in use;
- queries `amazon.aws.aws_ec2` for the AWS regions in use;
- queries `azure.azcollection.azure_rm` for the Azure resource group in use;
- skips a provider when no configured VM uses it;
- keeps only live instances whose Terraform resource names match configured
  VMs;
- creates functional inventory groups from each VM's `tags` array.

The JSON configuration remains the authority for logical placement and
grouping. The plugin supplies the bastion's functional tag because its purpose
is explicit in the configuration structure. Cloud APIs provide live existence
and current public addresses.

## Setup

Install Ansible with pipx, add the provider Python libraries to the same pipx
environment, and install the provider collections:

```sh
pipx install ansible-core
pipx runpip ansible-core install \
  -r infrastructure/ansible/requirements.txt

ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

Install the Azure collection dependency set into the same pipx environment:

```sh
pipx runpip ansible-core install \
  -r "$HOME/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt"
```

The repository requirements also install `kubernetes.core` and its controller
Python libraries. K3s application automation additionally expects `kubectl`
and Helm on the WSL/controller host; they connect through the local SSH tunnel
to the private API and are not installed on the cluster nodes. Install the
Helm Diff plugin as well so `kubernetes.core.helm` can distinguish real OCI
chart changes from no-op runs. Pin and verify the plugin according to its
upstream release instructions rather than installing an unversioned artifact.

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

For Azure, authenticate the CLI and select the subscription declared in the
project configuration:

```sh
az login
az account set --subscription <subscription-id>
```

Credentials must be available for every provider used by the current
configuration. Only the selected provider credential is needed when all VMs use
one cloud.

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

Hosts appear only after `terraform apply`. A mixed-cloud test should show the
corresponding `aws`, `azure`, and `gcp` groups. Functional tags create groups such as `bastion`,
`infrastructure`, `history`, `fetcher`, and `ui`; every non-bastion also joins
`workloads`.

## Normalized host variables

Every discovered host receives:

| Variable | Meaning |
| --- | --- |
| `internal_ip` | address from the VM's JSON configuration |
| `public_ip` | current address discovered from the provider |
| `oilscope_cloud` | `aws`, `azure`, or `gcp` |
| `oilscope_location` | logical location key from the configuration |
| `oilscope_tags` | functional tags from the VM definition |
| `oilscope_vm_name` | workload key from `vms`, or `bastion` for the top-level bastion |
| `oilscope_azure_subscription_id` | Azure subscription containing the VM; Azure hosts only |
| `oilscope_azure_resource_group` | Azure resource group containing the VM; Azure hosts only |
| `oilscope_azure_location` | Azure region containing the VM; Azure hosts only |
| `oilscope_azure_identity_id` | user-assigned identity resource ID used by AMA; Azure hosts only |
| `ansible_user` | provider-appropriate or explicitly overridden SSH user |
| `ansible_ssh_common_args` | environment-specific host-key and bastion routing options |
| `ansible_ssh_private_key_file` | optional key path from `OILSCOPE_SSH_KEY` |

For a bastion, `ansible_host` is its public address and both `ansible_port` and
`bastion_ssh_port` come from its top-level definition. Other VMs use their internal
address and port 22.

## SSH routing

The inventory plugin emits SSH connection variables directly; no inventory
`group_vars` files are required. AWS hosts connect as `ubuntu`, matching the
configured Ubuntu AMIs. Azure and GCP hosts use the alphabetically first
username from `ssh_users` in `project-config.json`. Override either default when necessary:

```sh
export OILSCOPE_SSH_USER=andri
```

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

Development hosts disable SSH host-key persistence because fixed internal
addresses are recreated with new host keys. Other environments accept new host
keys but reject changed keys. All connections use `IdentitiesOnly=yes`.

Inventory discovery does not provide cross-cloud routing. For application
deployment, the bastion and its private workloads must be mutually reachable.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `unknown plugin 'oilscope.platform.oilscope_cloud'` | rebuild and reinstall this repository's collection |
| `unknown plugin 'google.cloud.gcp_compute'` | install `requirements.yml` |
| `unknown plugin 'amazon.aws.aws_ec2'` | install `requirements.yml` |
| `unknown plugin 'azure.azcollection.azure_rm'` | install `requirements.yml` |
| `couldn't resolve module/action 'kubernetes.core.k8s'` | install `requirements.yml`, then rebuild this collection |
| missing GCP or AWS Python libraries | install `requirements.txt` with `pipx runpip ansible-core` |
| missing Kubernetes Python client or YAML support | install `requirements.txt` into the Ansible pipx environment |
| missing Azure Python libraries | install the Azure collection's `requirements.txt` as shown above |
| the `aws` group is empty | verify `aws sts get-caller-identity` with the selected profile |
| the `azure` group is empty | verify `az account show` and the configured subscription |
| the `gcp` group is empty | verify the active ADC account and configured project |
| a configured host is absent | confirm Terraform created it with the expected `<prefix>-<environment>-<VM key>` name |

Use `-vvv` to see which configured VM names were not returned by a provider.
