# The managed database

PostgreSQL runs in one of two places, and one word in the project configuration
decides which:

```json
"database": {
  "mode": "managed",
  "engine_version": "17",
  "size": "small",
  "storage_gb": 20,
  "name": "oil_tracker",
  "username": "oil_tracker",
  "backup_retention_days": 1,
  "deletion_protection": false
}
```

`self-hosted` is how the project always worked: the VM with the role `infra`
runs the PostgreSQL container, the queue between the fetcher and the history
service is PGMQ inside that database, and the UI keeps its sessions in a table
that pg_cron sweeps. The block is present in this mode too; only `mode` is
read, so switching is a one-word change and not the addition of ten lines.

`managed` moves PostgreSQL to the cloud's service - Cloud SQL on GCP, RDS on
AWS - in a subnet of its own. The infra VM does not disappear: it changes what
it carries. Neither managed service offers the PGMQ extension, so the queue
moves to a RabbitMQ container on that VM, and the UI sessions move to a Redis
container next to it. The database keeps only the data.

| | self-hosted | managed |
| --- | --- | --- |
| observations | PostgreSQL container on `infra` | Cloud SQL / RDS in the `database` subnet |
| queue fetcher → history | PGMQ in that database | RabbitMQ on `infra`, exchange `oil.price.events`, quorum queue `history.price-observations` |
| UI sessions | `ui_sessions` table, swept by pg_cron | Redis on `infra`, keys that expire on their own |
| publish ledger | `published_queue_events`, same transaction as the send | `published_queue_events` in the managed database; claim, then publish |
| schema migrations | `migrate` job on `infra` against the container | the same job on `infra` against the endpoint, over TLS |
| ports `infra` opens | 5432 to fetcher, history, ui | 5672 and 6379 to the same three |
| clients connect with | `sslmode=disable` | `sslmode=require` |

The services carry both paths. The fetcher publishes through one of two
`Publisher` implementations, the history service consumes through
`PGMQConsumer` or `AMQPConsumer`, the UI stores sessions in PostgreSQL or
Redis. Each is chosen by one environment variable - `QUEUE_BACKEND`,
`SESSION_BACKEND` - that Ansible derives from the same `mode` Terraform reads.
Nothing else in the services knows which one is running, and the same images
serve both modes.

## What it costs in guarantees

On PGMQ the claim in `published_queue_events` and the send happen in one
transaction, so a batch is published exactly once. Over AMQP the claim is
committed first and the publish follows; if the broker refuses, the claim is
released again. That narrows the window rather than closing it: a crash between
the two drops one batch, and the next scheduled run collects those prices
again. The history side keeps its idempotency either way - the unique index on
`(instrument_code, scheduled_for)` turns a redelivery into a no-op.

On RabbitMQ the retry limit is the broker's: the queue is a quorum queue with
`x-delivery-limit`, and a message that came back that many times is
dead-lettered into `history.price-observations.dead` - the equivalent of the
PGMQ archive table. Permanently invalid messages go there at once.

## Configuration

Everything provider-independent is in the `database` block above. What has a
different name on each cloud lives in the cloud profiles:

```json
"clouds": {
  "gcp": {
    "subnets": { "database": ["10.0.2.0/28"] },
    "database_sizes": { "small": "db-f1-micro", "medium": "db-g1-small", "large": "db-custom-2-7680" }
  },
  "aws": {
    "subnets": { "database": ["10.1.2.0/28", "10.1.3.0/28"] },
    "database_sizes": { "small": "db.t4g.micro", "medium": "db.t4g.small", "large": "db.t4g.medium" }
  }
}
```

`size` is a label into `database_sizes`, the way a VM's `size` is a label into
`machine_sizes`. AWS needs two database ranges because RDS refuses a DB subnet
group that does not span two availability zones, even for a single instance;
GCP needs one, for the endpoint.

`engine_version` is pinned to `17` by the schema: the self-hosted image ships
PostgreSQL 17, and keeping both modes on one major means a dump moves between
them without a version jump. `service_ports` gains `amqp` and `redis`, and the
infra, history, fetcher and ui VMs gain the secrets the broker and the cache
need:

| VM | secret mappings added |
| --- | --- |
| infra | `RABBITMQ_PASSWORD`, `REDIS_PASSWORD` |
| history, fetcher | `RABBITMQ_PASSWORD` |
| ui | `REDIS_PASSWORD` |

The mappings are static, so the containers exist in self-hosted mode too and
`upload_secret_versions` asks for their values in both modes. That is simpler
than conditional mappings, and it means a switch never has to be preceded by a
secret upload.

A managed database is reachable only inside one VPC. Terraform therefore
refuses a managed configuration whose workloads are not all on the cloud that
hosts the infra VM.

## A network of its own

The database subnet has no route to the internet in either direction. On GCP it
is not listed under Cloud NAT and has no Private Google Access; on AWS it hangs
off a route table that knows only the VPC range.

**GCP** reaches Cloud SQL through Private Service Connect. The instance has no
public address and no private-services-access peering: it publishes a service
attachment, and Terraform allocates an address in the database subnet and
points a forwarding rule at that attachment. That address - not a Google-owned
one in a peered range - is what the workloads see as `DATABASE_HOST`. The
instance accepts encrypted connections only (`ssl_mode = ENCRYPTED_ONLY`), so
the clients set `sslmode=require`; the server certificate is not verified,
which is the accepted trade-off for a private network without a DNS zone or
the Cloud SQL Auth Proxy on every VM. Needs `sqladmin.googleapis.com` enabled.

**AWS** puts RDS in a DB subnet group over the two database subnets, not
publicly accessible, behind a security group that admits port 5432 from the
security groups of the three workloads and of the infra instance - the latter
because it runs the migrations. The engine family's default parameter group
already forces TLS.

The firewall rules to the infra VM follow the mode: 5432 in self-hosted mode,
5672 and 6379 in managed mode, from the same three workloads. A Private
Service Connect endpoint is not a VM, so it needs no rule of its own on GCP.

## Where the password lives

Not in Terraform - not in the configuration, the plan or the state. Beyond
that the two clouds are handled differently, because they offer different
things, and the `managed_database_credentials` playbook does the reconciling:

- **AWS** generates the master password itself and keeps it in a Secrets
  Manager secret of its own (`manage_master_user_password`). The playbook reads
  that secret and puts the value into the project's `POSTGRES_PASSWORD`
  container, the one `resolve_secrets` and the Compose environment already
  read. The application role is the master user. The operator needs
  `rds:DescribeDBInstances` and `secretsmanager:GetSecretValue` on the
  RDS-managed secret, plus the `PutSecretValue` right every version manager
  already has.
- **GCP** creates no application role by itself. The playbook takes the
  password from the environment variable `upload_secret_versions` reads for
  the container (`DB_PASSWORD` for `oilscope-dev-db-password`), or, when that
  is unset, from the container's latest version in Secret Manager, and creates
  or updates the role through the Cloud SQL Admin API with the password in the
  request body - never on a command line. The operator needs
  `roles/cloudsql.admin`.

The playbook runs on the operator's machine, not on a VM: creating a database
role is administrative, and no workload should hold that right.

RDS generates passwords from an alphabet that includes characters a URL
cannot carry unescaped. The password therefore reaches the Compose file twice:
as the value itself for the places that read it directly, and percent-encoded
(`RABBITMQ_PASSWORD_URL`, `REDIS_PASSWORD_URL`) for the places that build a
URL out of it.

## How Ansible finds the database

Terraform knows the endpoint, but its state is not something Ansible should
have to open. The endpoint carries a name derived from `name_prefix` and
`environment` - `oilscope-dev-database-endpoint` on GCP, `oilscope-dev-database`
on AWS - so the `oilscope_cloud` inventory plugin asks the cloud API for it
directly whenever the configuration says `managed`, and sets
`oilscope_managed_database_host` on every host. The group variables turn that
into `oilscope_database_host`, which every workload role reads. Set
`discover_database: false` in the inventory file to skip the lookup and pass
`-e oilscope_managed_database_host=<address>` instead.

`terraform output database` prints the same host, port, database and role
name - and on AWS the ARN of the RDS-managed secret - and never a password.

## Switching over

The container on `infra` disappears only when `deploy_workloads` applies the
managed mode, and the managed instance disappears only when `terraform apply`
runs in self-hosted mode. So in each direction there is a window in which both
databases exist and the data can move. The `migrate_database` playbook does the
moving: it stops the fetcher, waits for the PGMQ queue to drain when the source
is the container, dumps the public schema minus the sessions and the publish
ledger, restores the rows into the target, compares the counts and starts the
fetcher again. The dump stays under `/var/tmp/oilscope-transfer` on the VM -
the only copy if a restore has to be repeated.

### Self-hosted to managed

1. Set `"mode": "managed"`. Make sure `RABBITMQ_PASSWORD` and `REDIS_PASSWORD`
   have been uploaded (`upload_secret_versions`).
2. `terraform apply` - creates the subnet, the instance (Cloud SQL takes about
   ten minutes) and the endpoint, and switches the firewall to 5672/6379. The
   VMs are untouched. Until the next step finishes the workloads cannot reach
   the container any more; the switch-over is downtime.
3. `ansible-playbook oilscope.platform.managed_database_credentials -e project_config_path=...`
4. `ansible-playbook oilscope.platform.migrate_database -i ... -e project_config_path=... -e database_transfer_direction=to_managed`
5. `ansible-playbook oilscope.platform.deploy_workloads -i ... -e project_config_path=...`
   - on `infra`, RabbitMQ and Redis replace PostgreSQL; the services point at
   the endpoint.

### Managed to self-hosted

1. Set `"mode": "self-hosted"`.
2. `ansible-playbook oilscope.platform.deploy_workloads ...` - PostgreSQL comes
   back on `infra` (its volume survived, if nobody removed it), the services
   switch to PGMQ and the sessions table. The managed instance is still there
   and reachable from the VPC.
3. `ansible-playbook oilscope.platform.migrate_database ... -e database_transfer_direction=to_self_hosted -e database_transfer_managed_host=<endpoint>`
   - the configuration no longer names the endpoint, so it is passed in;
   `terraform output database` still shows it. A container that already
   holds observations is refused unless `-e database_transfer_force=true`
   empties it first.
4. `terraform apply` - destroys the instance, the endpoint and the subnet, and
   returns 5432 to `infra`.

Messages still in RabbitMQ and sessions in Redis are not carried over in
either direction: the queue is drained before a self-hosted dump, and sessions
are UI preferences that come back as defaults.

## Things the clouds refuse

A deleted Cloud SQL instance keeps its name reserved for about a week;
re-creating it under the same `name_prefix` and `environment` fails until then.
For create-destroy cycles while testing, a different `environment` sidesteps
it.

`backup_retention_days` above 1 is rejected outright by an AWS free-tier
account (`FreeTierRestrictionError`). Nothing is wrong with the configuration;
the limit belongs to the account. One day keeps automated backups and
point-in-time recovery on in both clouds; zero turns them off, and makes RDS
noticeably quicker to create and destroy.

The pg17 image will not start on a data directory written by PostgreSQL 18.
An environment that ran the earlier image has to recreate the
`petroscope-postgres-data` volume - or dump from 18 and restore - before the
first deployment of the current image.
