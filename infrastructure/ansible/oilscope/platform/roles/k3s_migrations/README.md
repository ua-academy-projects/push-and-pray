# K3s database migrations role

Runs the repository's existing `petroscope-migrate` container as a Kubernetes
Job from the local Ansible controller. The database image already contains
`database/migrations/*.sql`, `psql`, `pg_isready`, and the migration entrypoint,
so this role does not duplicate SQL files or migration logic.

The Job connects to the CloudNativePG `postgresql-rw` Service on the configured
`service_ports.postgresql` port with the
`POSTGRES_PASSWORD` key from the `<name-prefix>-application` Secret and pulls
the private database image with `<name-prefix>-registry`. It passes
`DATABASE_MODE=self_managed`, so all migrations run, including the PostgreSQL
session tables, PGMQ queue, and publisher tracking table. The CloudNativePG
`Database` resource creates the required extensions before this Job starts.

The Job name includes a hash of the database image reference and migration
mode. A completed Job is therefore reused on an unchanged run, while changing
the configured image tag creates a new Job. A failed Job is deleted and
recreated on the next run. The role waits for completion and includes pod logs
in its failure message when they are available.

With the private K3s API reachable through Tailscale, invoke the role after the
application Secrets and CloudNativePG cluster exist:

```bash
ansible-playbook oilscope.platform.migrate_k3s_database \
  -i localhost, \
  -e k3s_migrations_config_file="$PWD/project-config.json"
```
