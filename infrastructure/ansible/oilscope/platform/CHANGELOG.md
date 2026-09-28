# Changelog

All notable changes to the `oilscope.platform` collection.

This project follows [semantic versioning](https://semver.org/).

## 0.1.0

- Added dynamic AWS, Azure, and GCP inventory with bastion-based SSH routing.
- Added workload deployment roles and ordered deployment playbooks.
- Added AWS CloudWatch Agent and GCP Ops Agent configuration.
- Added Azure Monitor Agent deployment and Terraform-managed Azure
  observability, including bastion host monitoring and direct workload
  container logging through the host syslog socket.
- Added AWS, Azure, and GCP secret resolution and secret-version upload
  automation.
- Added one idempotent deployment entry point with convergent secret synchronization
  and automatic provider-specific observability.
