# Legacy Vagrant deployment

This directory preserves the previous local multi-VM Vagrant deployment from the
last version on `main` before the Terraform and Ansible deployment replaced it.
It is retained as an artifact of the earlier sprint, including its Vagrantfile,
operator configuration example, host commands, and guest provisioning scripts.

Current production-style deployments use `infrastructure/terraform` to provision
AWS or GCP and `infrastructure/ansible` to configure workloads. Nothing in the
current Terraform, dynamic inventory, or Ansible playbooks invokes this directory.

The snapshot intentionally preserves its original paths and assumptions for
historical review; it is not maintained or tested as a current deployment path.
Do not use it to operate the AWS or GCP environments.
