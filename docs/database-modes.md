# PostgreSQL infrastructure modes

`database_mode` is the single project-wide database architecture switch. It is
defined beside `default_cloud` and `default_location` in `project-config.json`.

| `database_mode` | `default_cloud` | PostgreSQL | Messaging | UI sessions |
| --- | --- | --- | --- | --- |
| `postgres_extensions` | `aws`, `gcp`, or `azure` | PostgreSQL container on the first K3s server | PGMQ | PostgreSQL hstore/pg_cron |
| `managed` | `aws` | Private Amazon RDS for PostgreSQL | RabbitMQ Deployment | Redis Helm release |
| `managed` | `gcp` | Private Cloud SQL for PostgreSQL | RabbitMQ Deployment | Redis Helm release |
| `managed` | `azure` | Private PostgreSQL Flexible Server | RabbitMQ Deployment | Redis Helm release |

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

For Azure, use `default_cloud: "azure"` with `database_mode: "managed"`; see
[Azure configuration](azure.md) for private networking and administrator-password
handoff to the existing secret workflow.

There is no separate provider-specific database switch. In managed mode `default_cloud` is
the only provider selector. Database-consuming K3s nodes must use that cloud
and the default location to reach the private endpoint. Azure Terraform checks
that placement. Review AWS/GCP placement before applying Terraform because
their provider modules do not enforce this managed-mode constraint. A K3s
cluster spanning locations also requires working private node-to-node routes;
the current Terraform modules do not create cross-cloud peering.

## Private networking

RDS is placed in two dedicated private DB subnets in distinct availability
zones inside the existing default-location VPC. Their dedicated route table has
no Internet route, and RDS has no public endpoint. Its security group accepts
port 5432 only from K3s node security groups in the default VPC.

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

The selected first K3s server runs the database preparation playbook in both
modes. In `postgres_extensions` it runs PostgreSQL and migrations. In `managed`
it runs migrations and application-role provisioning against the private
managed endpoint. RabbitMQ is a Kubernetes Deployment; Redis is a Helm release
in the `oilscope` namespace.
