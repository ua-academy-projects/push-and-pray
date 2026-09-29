# K3s database migrations role

Runs the repository's existing `petroscope-migrate` container as a Kubernetes
Job from the local Ansible controller. The database image already contains
`database/migrations/*.sql`, `psql`, `pg_isready`, and the migration entrypoint,
so this role does not duplicate SQL files or migration logic.

The Job connects to the internal `postgresql` Service on the configured
`service_ports.postgresql` port with the
`POSTGRES_PASSWORD` key from the `<name-prefix>-application` Secret and pulls
the private database image with `<name-prefix>-registry`. It passes
`DATABASE_MODE=managed`, selecting the schema used by RabbitMQ and Redis:
migrations 001 and 002 run, while the PostgreSQL session, PGMQ queue, and PGMQ
publisher migrations 003 through 005 are skipped.

This migration-runner value describes the application integration layout; it
does not mean Terraform provisions a cloud-managed database. The K3s project
configuration keeps `database.mode` set to `self_managed` because PostgreSQL is
installed inside the cluster by Helm.

The Job name includes a hash of the database image reference and migration
mode. A completed Job is therefore reused on an unchanged run, while changing
the configured image tag creates a new Job. A failed Job is deleted and
recreated on the next run. The role waits for completion and includes pod logs
in its failure message when they are available.

Keep the SSH tunnel to the private K3s API running, then invoke the role after
the application Secrets and PostgreSQL release exist:

```bash
ansible-playbook oilscope.platform.migrate_k3s_database \
  -i localhost, \
  -e k3s_migrations_config_file="$PWD/project-config.json"
```
