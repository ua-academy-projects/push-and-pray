# Session cache role

Starts the Redis container on the infra VM and waits for it to become healthy.
Used only when `database.mode` is `managed`: the UI sessions then move out of
the PostgreSQL table into Redis, whose key expiry does what pg_cron did for the
table.

Redis runs with `requirepass`, an append-only file synced every second and the
`noeviction` policy, so a full cache refuses writes instead of dropping
sessions silently. The data lives in a named volume.

Starting the cache with `--remove-orphans` retires the PostgreSQL container
left by a self-hosted deployment. Its data volume is kept, so switching back
finds the data where it was.

## Required variables

- `session_cache_password`: the Redis password. Marked `no_log`.

## Optional variables

- `session_cache_bind_address`, `session_cache_host_port`: where Redis listens
  on the VM; default to `0.0.0.0` and `6379`.
- `session_cache_health_retries`, `session_cache_health_delay`: health polling
  controls, defaulting to 30 attempts every 2 seconds.
- `session_cache_compose_project_dir`, `session_cache_compose_file`,
  `session_cache_compose_project_name`: Compose location.
- `session_cache_compose_environment`: additional non-secret Compose
  environment.

## License

GPL-2.0-or-later
