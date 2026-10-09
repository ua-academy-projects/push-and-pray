# Multi-cloud infrastructure

The project JSON remains the configuration source for Terraform and Ansible.
Use `default_cloud` with optional per-VM `cloud` overrides.

Terraform keeps the original module names and groups cloud-specific modules under
`modules/aws`, `modules/gcp` and `modules/azure`. The mixed AWS/GCP identity
module remains at `modules/iam`. Interpretation stays inside these
modules; root locals only read the JSON. Provider settings use the JSON location
dictionaries.

Ansible uses the same selection. Its inventory wrapper delegates discovery to
`amazon.aws.aws_ec2`, `google.cloud.gcp_compute` or
`azure.azcollection.azure_rm` and groups hosts by cloud and role. Exactly one
global bastion is used as the SSH jump host. Terraform-bootstrapped Tailscale
subnet routers make every cloud's non-overlapping private CIDR reachable from
that bastion and from the other K3s nodes.

Both cloud dictionaries include five named locations and a preserved
`default` alias. One location is selected for a deployment, not all five.
Machine sizes are unchanged. Terraform attaches the official Tailscale
cloud-init payload to each VM on first creation; ordinary application setup
continues through Ansible.

See the [Terraform guide](../infrastructure/terraform/README.md) for layout,
region/image selection, optional disks, SSH and known networking limitations.
Before using existing resources, read the
[state migration checklist](terraform-module-migration.md).
