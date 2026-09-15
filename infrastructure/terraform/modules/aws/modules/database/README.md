# aws/database

RDS for PostgreSQL in the database subnets.

Created only when `database.mode` is `managed` and this cloud hosts the `infra`
VM. The instance is not publicly accessible, sits in a DB subnet group over the
two database subnets, and admits connections on its port from the security
groups of the three workloads and of the infra instance, which runs the schema
migrations. The engine family's default parameter group forces TLS, so clients
set `sslmode=require`.

RDS generates the master password itself and keeps it in Secrets Manager
(`manage_master_user_password`), so Terraform never handles the value. The
`managed_database_credentials` Ansible playbook copies it into the project's
own secret container, the one the workloads already read.

Inputs are resolved by the caller: the instance class comes from
`database_sizes` in the cloud profile, the subnets from the network module,
the client groups from the firewall module.
