# Message broker role

Starts the RabbitMQ container on the infra VM and waits for it to become
healthy. Used only when `database.mode` is `managed`: a managed PostgreSQL has
no PGMQ extension, so the queue between the fetcher and the history service
moves to a broker, and the broker takes the place PostgreSQL used to hold on
this VM.

The topology - the exchange, the quorum queue with its delivery limit, the
dead-letter pair - is declared by the services themselves, so this role only
provides a broker with one vhost and one user. `RABBITMQ_DEFAULT_PASS` is read
by the image once, on first start; the role therefore verifies the current
password against the running broker and sets it when it differs, so a rotated
secret takes effect on the next deployment.

Starting the broker with `--remove-orphans` retires the PostgreSQL container
left by a self-hosted deployment. Its data volume is kept, so switching back
finds the data where it was.

## Required variables

- `message_broker_password`: password of the broker user. Marked `no_log`.

## Optional variables

- `message_broker_user`, `message_broker_vhost`: both default to `oil_tracker`.
- `message_broker_bind_address`, `message_broker_host_port`: where the broker
  listens on the VM; default to `0.0.0.0` and `5672`.
- `message_broker_health_retries`, `message_broker_health_delay`: health
  polling controls, defaulting to 30 attempts every 2 seconds.
- `message_broker_compose_project_dir`, `message_broker_compose_file`,
  `message_broker_compose_project_name`: Compose location.
- `message_broker_compose_environment`: additional non-secret Compose
  environment.

## License

GPL-2.0-or-later
