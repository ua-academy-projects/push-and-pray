# Database transfer role

Moves the observations between the PostgreSQL container on the infra VM and
the managed instance, in either direction. Runs on the infra VM, because that
is the one machine inside the VPC that can reach both.

The two modes keep different things in the database, so not everything moves:

| Table | Moves? | Why |
| --- | --- | --- |
| `price_observations`, any future application table | yes | the data |
| `pgmq.*`, `cron.*` | no | extension state; drained or recreated, and a managed server has neither extension |
| `ui_sessions` | no | UI preferences, recreated from defaults |
| `published_queue_events` | no | the publish ledger starts over on the other side |

The dump is `pg_dump --format=custom` from the source; the target gets its
schema from the migrations and then a `--data-only` restore. The row count is
compared afterwards. A target that already holds observations is refused
unless `database_transfer_force` is set, in which case it is emptied first.

The dump file stays under `database_transfer_dump_dir` on the VM until removed
by hand: it is the only copy if the restore has to be repeated.

## Directions

`to_managed`: run after `terraform apply` and `managed_database_credentials`,
before `deploy_workloads` replaces the container with the broker and the
cache. The queue is drained first - a message still in it would be lost with
the container.

`to_self_hosted`: run after the configuration says `self-hosted` again and
`deploy_workloads` has brought the container back, before `terraform apply`
destroys the instance. The configuration no longer names a managed database,
so `database_transfer_managed_host` has to be passed in.

The fetcher is stopped by the `migrate_database` playbook around the transfer
so that nothing is written while the data is in flight.

## Required variables

- `database_transfer_postgres_password`: the application role's password on
  the managed side. Passed to the one-off containers by name, never as an
  argument. Marked `no_log`.
- `database_transfer_managed_host`: the managed endpoint; defaults to what the
  inventory plugin discovered, which only exists while the configuration says
  `managed`.

## Optional variables

- `database_transfer_direction`: `to_managed` (default) or `to_self_hosted`.
- `database_transfer_managed_port`, `database_transfer_managed_sslmode`:
  default to the configured PostgreSQL port and `require`.
- `database_transfer_force`: empty a non-empty target instead of refusing.
- `database_transfer_drain_retries`, `database_transfer_drain_delay`: how long
  to wait for the queue to empty; default to 60 attempts every 5 seconds.
- `database_transfer_dump_dir`: defaults to `/var/tmp/oilscope-transfer`.
- `database_transfer_postgres_user`, `database_transfer_postgres_name`: both
  default to `oil_tracker`.
- `database_transfer_compose_project_dir`, `database_transfer_compose_file`,
  `database_transfer_compose_project_name`: Compose location.

## License

GPL-2.0-or-later
