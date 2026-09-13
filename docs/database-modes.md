# PostgreSQL infrastructure modes

`database_mode` is the single project-wide database architecture switch. It is
defined beside `default_cloud` and `default_location` in `project-config.json`.

| `database_mode` | `default_cloud` | PostgreSQL | Messaging | UI sessions |
| --- | --- | --- | --- | --- |
| `postgres_extensions` | `aws` or `gcp` | PostgreSQL container on the `database` VM | PGMQ | PostgreSQL hstore/pg_cron |
| `managed` | `aws` | Private Amazon RDS for PostgreSQL | RabbitMQ on `history` | Redis on `ui` |
| `managed` | `gcp` | Private Cloud SQL for PostgreSQL | RabbitMQ on `history` | Redis on `ui` |

Self-managed mode:

```json
{
  "default_cloud": "aws",
  "database_mode": "postgres_extensions"
}
```

Managed AWS (RDS):

```json
{
  "default_cloud": "aws",
  "database_mode": "managed"
}
```

Managed GCP (Cloud SQL):

```json
{
  "default_cloud": "gcp",
  "database_mode": "managed"
}
```

There is no separate RDS/Cloud SQL switch. In managed mode `default_cloud` is
the only provider selector. Database-consuming workload VMs must use that cloud
and the default location; Terraform rejects mixed-cloud managed topologies
because they cannot satisfy the private-connectivity requirement.

## Private networking

RDS is placed in two dedicated private DB subnets in distinct availability
zones inside the existing default-location VPC. Their dedicated route table has
no Internet route, and RDS has no public endpoint. Its security group accepts
port 5432 only from the `database` migration host and the `history` workload
security groups.

Cloud SQL has public IPv4 disabled. The GCP network module reserves an internal
VPC peering range and establishes Private Services Access through
`servicenetworking.googleapis.com`; Cloud SQL receives a private IP on that
connection. A Cloud SQL Auth Proxy or language connector is not required for
this VM-to-private-IP topology.

## Terraform to Ansible handoff

After `terraform apply`, the non-secret `managed_database` output contains the
private host, port, database name, SSL mode, and provider instance identifier.
The `oilscope.platform.oilscope` inventory plugin reads this output and exposes
it as the `managed_database` inventory variable. Ansible then renders the
correct standard connection settings without a manual `.env` edit.

RDS generates and stores its administrator password in AWS Secrets Manager;
Ansible resolves the generated secret by its non-secret ARN. Cloud SQL's
administrator password and all application, RabbitMQ, and Redis passwords use
the existing provider-independent Ansible Secret Manager/Secrets Manager flow.
Secret values remain in memory and are never emitted as Terraform outputs.

The `database` VM remains in both modes. In `postgres_extensions` it runs
PostgreSQL and migrations. In `managed` it stops the local PostgreSQL container
and runs migrations plus application-role provisioning against the private
managed endpoint. RabbitMQ and Redis retain their original placements on the
`history` and `ui` VMs.
