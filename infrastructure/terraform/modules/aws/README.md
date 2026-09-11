# AWS stack module

This module owns the complete AWS stack. Its nested `config` module interprets
the shared JSON and resolves AWS profiles; `network` and `vm` contain the
provider resources. Nothing outside `modules/aws` contains AWS implementation
details.

If no VM selects AWS, the module creates no resources and returns empty maps.
Private workloads require an AWS bastion for Ansible access. The mixed root
connects the AWS and GCP networks through a private IPsec VPN.

When `manage_db=true` and `database.cloud=aws`, the module creates private RDS
PostgreSQL, an encrypted GP3 volume, a DB subnet group spanning two configured
Availability Zones, and a dedicated security group. Set a new
`database.generation` for each monthly restore. Dev defaults intentionally skip
the final snapshot when `backup_on_delete=false`.
