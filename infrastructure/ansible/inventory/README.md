# Multi-cloud dynamic inventory

`oilscope.yml` uses the `oilscope.platform.oilscope_gcp` wrapper. The plugin
keeps its historical name for compatibility, but discovers GCP Compute Engine,
AWS EC2 and Azure Linux VMs.

The wrapper reads the same project JSON as Terraform, applies `default_cloud`
and each VM's optional `cloud` override, and loads only the provider inventory
plugins required by that configuration.

Terraform attaches these tags or labels to every VM:

- `application`;
- `environment`;
- `role`;
- `cloud` (`gcp`, `aws` or `azure`);
- `k3s_role` and `k3s_bootstrap` on K3s nodes.

The inventory creates role groups, the `cloud_gcp`, `cloud_aws` and
`cloud_azure` groups, plus `k3s_servers`, `k3s_agents` and `k3s_bootstrap`.
Exactly one VM is in `bastion`. Every workload keeps its provider-private IP as
`ansible_host`; `group_vars/workloads.yml` sends SSH through that one bastion.
Terraform cloud-init joins the VMs to Tailscale, and one K3s server per active
cloud advertises its non-overlapping private CIDR. The bastion can therefore
reach private addresses in every cloud without provider-specific bastions.

Terraform also attaches non-secret database and queue connection metadata.
Passwords are never stored in VM tags or metadata; `resolve_secrets` reads them
from the selected secret manager during deployment.

## Controller setup

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

Use Application Default Credentials for GCP, the normal AWS SDK credential
chain for AWS, and an active `az login` session for Azure.

```sh
export OILSCOPE_PROJECT_CONFIG=/absolute/path/to/dev.json
export OILSCOPE_SSH_KEY=/absolute/path/to/private-key
ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph
```

For the complete deployment, use `scripts/configure-ansible.sh`; it builds and
installs the repository collection before loading this inventory. Cross-cloud
bootstrap and verification are documented in
[`docs/tailscale.md`](../../../docs/tailscale.md).
