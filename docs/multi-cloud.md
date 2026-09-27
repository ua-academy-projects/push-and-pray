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
`azure.azcollection.azure_rm`, groups hosts by cloud and role, and routes each
private workload through the bastion in that same cloud.

Both cloud dictionaries include five named locations and a preserved
`default` alias. One location is selected for a deployment, not all five.
Machine sizes are unchanged. Startup/cloud-init sources remain in the
repository, but Terraform does not attach them to VMs.

See the [Terraform guide](../infrastructure/terraform/README.md) for layout,
region/image selection, optional disks, SSH and known networking limitations.
Before using existing resources, read the
[state migration checklist](terraform-module-migration.md).
