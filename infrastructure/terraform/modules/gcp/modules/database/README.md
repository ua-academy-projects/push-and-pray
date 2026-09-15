# gcp/database

Cloud SQL for PostgreSQL, reached over Private Service Connect.

Created only when `database.mode` is `managed` and this cloud hosts the `infra`
VM. The instance has no public address and no private-services-access peering:
it publishes a service attachment, and this module allocates an address in the
database subnet and points a forwarding rule at that attachment. The address is
what every workload sees as `DATABASE_HOST`. The instance accepts encrypted
connections only, so clients set `sslmode=require`.

The application role is not created here. Cloud SQL needs a password to create
one, and a password given to Terraform ends up in the plan and the state. The
`managed_database_credentials` Ansible playbook creates it through the Admin
API instead, with the same value it uploads to the project's secret container.

Inputs are resolved by the caller: the tier comes from `database_sizes` in the
cloud profile, the subnet from the network module.
