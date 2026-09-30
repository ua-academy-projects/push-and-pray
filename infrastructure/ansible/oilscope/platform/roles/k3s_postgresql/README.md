# K3s PostgreSQL role

Runs on the local Ansible controller after the CloudNativePG operator is ready.
The role declares the repository's existing `database` image as PostgreSQL 18
through a namespaced `ImageCatalog`, then creates a multi-instance PostgreSQL
cluster in the application namespace.

The application image inherits the Docker Official Image's `postgres` account,
whose UID and GID are both `999`. The role passes those IDs to CloudNativePG
instead of using the operator defaults of `26`, so the instance manager and
PostgreSQL run as the account that exists in the image.

The instance count comes from `k3s.data_services.postgresql.instances`, whose
schema-enforced minimum is two. With two instances, CloudNativePG runs one
writable primary and one streaming replica. Every
instance receives its own `local-path` persistent volume, and required pod
anti-affinity spreads the database instances across different Kubernetes
nodes. Applications connect to the operator-managed `postgresql-rw` Service,
which always targets the current primary.

The application owner credentials come from the
`<name-prefix>-postgresql-owner` basic-auth Secret created by the K3s secrets
role. The private database image is pulled with the existing registry Secret.
Superuser login is disabled. A declarative `DatabaseRole` adopts the bootstrap
owner and keeps its password synchronized when that Secret is rotated.

After the cluster becomes ready, the role reconciles a `Database` resource for
`oil_tracker` and creates the `hstore`, `pg_cron`, `pgcrypto`, and `pgmq`
extensions. It grants the non-superuser application owner `USAGE` on the
operator-owned `cron` schema and configures pg_cron to execute jobs as
background workers, avoiding separate password-authenticated localhost
connections. It also grants `USAGE` and `CREATE` on the PGMQ schema plus
`SELECT` and `INSERT` on its queue catalog. This lets the migration runner
create application-owned queue tables while leaving the extension itself under
operator control. The database migration Job can then schedule its cleanup
task and initialize PGMQ without receiving superuser privileges.
