# Multi-cloud infrastructure

The project JSON remains the configuration source for Terraform and Ansible.
Use `default_cloud` with optional per-VM `cloud` overrides.

Terraform now calls small, flat modules for network, security, VMs, IAM, GCP
APIs and secrets. Interpretation stays inside these modules; root locals only
read the JSON. Provider settings use the JSON location dictionaries.

Both cloud dictionaries include five named locations and a preserved
`default` alias. One location is selected for a deployment, not all five.
Machine sizes are unchanged. Startup/cloud-init sources remain in the
repository, but Terraform does not attach them to VMs.

See the [Terraform guide](../infrastructure/terraform/README.md) for layout,
region/image selection, optional disks, SSH and known networking limitations.
Before using existing resources, read the
[state migration checklist](terraform-module-migration.md).
