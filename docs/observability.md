# Observability

Every host ships its journal and host metrics to the cloud it runs on.
Containers write to the journal, so application output travels the same road
as sshd, the kernel and Docker itself, and nothing in the Compose files or the
Docker configuration names a cloud.

```text
container stdout/stderr ──journald driver──► journal ──agent──► Cloud Logging / CloudWatch Logs
host CPU, memory, disk, network ─────────────────────agent──► Cloud Monitoring / CloudWatch Metrics
```

| Cloud | Agent | Logs land in | Metrics land in |
| --- | --- | --- | --- |
| GCP | Ops Agent | `projects/<project_id>/logs/journald` | Cloud Monitoring, `agent.googleapis.com/*` |
| AWS | Fluent Bit + CloudWatch agent | log group `/<name_prefix>-<environment>/journald`, one stream per host | CloudWatch namespace `CWAgent` |

## Who does what

- `infrastructure/terraform/modules/<cloud>/modules/logging` grants each VM's
  identity — the workloads and the bastion — the right to write logs, sets
  retention, and on AWS creates the log group.
- `.../modules/monitoring` grants the right to write metrics, defines the
  watched metrics and their thresholds, and draws the dashboard.
- `.../modules/alerting` turns those metrics and the journal into e-mail, and
  keeps a monthly budget.
- `host_baseline` keeps the journal on disk, caps it at 500 MB and raises the
  per-unit rate limit, because every container logs through `docker.service`.
- `docker_engine` writes `/etc/docker/daemon.json` with the `journald` logging
  driver and attaches the Compose project and service labels to every line.
  It also runs `docker-events.service`, which writes one JSON line to the
  journal per container exit, with the container's name and exit code.
- `observability_agent` installs the cloud's agent and configures it to parse
  container lines as JSON and use the application's own log level as the
  entry's severity.

The deployment playbooks apply all three; `oilscope.platform.observability`
applies the agent alone to every host.

## What the applications must do

Log one JSON document per line to stdout, with a `level` key and a `message`
or `msg` key. Any other key becomes a queryable field. A plain-text line still
arrives, but with no severity of its own — and because Docker marks every
stderr line as an error, a plain-text service that logs to stderr shows up
red in Logs Explorer regardless of what it wrote.

## What is collected

| Source | Journal fields to filter on |
| --- | --- |
| Every container's output | `CONTAINER_NAME`, `IMAGE_NAME`, `COM_DOCKER_COMPOSE_SERVICE`, plus the JSON keys the application logged |
| `docker.service` | `_SYSTEMD_UNIT="docker.service"` |
| sshd, sudo, PAM | `_SYSTEMD_UNIT="ssh.service"`, `_COMM="sudo"` |
| Kernel, including OOM kills | `_TRANSPORT="kernel"` |
| systemd, cloud-init, unattended-upgrades, apt | `_SYSTEMD_UNIT`, `SYSLOG_IDENTIFIER` |

Not collected: per-container CPU and memory, healthcheck state, application
metrics, PostgreSQL internals.

## Queries

Logs Explorer:

```text
logName="projects/<project_id>/logs/journald"
jsonPayload.CONTAINER_NAME="petroscope-history-1"
severity>=WARNING
```

```text
logName="projects/<project_id>/logs/journald"
jsonPayload.CONTAINER_NAME="oilscope-proxy-traefik-1"
jsonPayload.DownstreamStatus>=500
```

```text
logName="projects/<project_id>/logs/journald"
jsonPayload._TRANSPORT="kernel"
jsonPayload.MESSAGE=~"Out of memory"
```

CloudWatch Logs Insights, on the environment's log group:

```text
fields @timestamp, CONTAINER_NAME, level, message
| filter CONTAINER_NAME = "petroscope-fetcher-1" and level = "ERROR"
| sort @timestamp desc
```

```text
fields @timestamp, ClientHost, RequestPath, DownstreamStatus, Duration
| filter CONTAINER_NAME = "oilscope-proxy-traefik-1" and DownstreamStatus >= 500
```

## Dashboard and alerts

Every VM, the bastion included, is watched for the same five things:

| | GCP metric | AWS metric | Alert when |
| --- | --- | --- | --- |
| CPU | `instance/cpu/utilization` | `CPUUtilization` | above 0.75 (75 %) for 5 min |
| Memory | `agent.googleapis.com/memory/bytes_used` | `CWAgent mem_used` | above 1.5 GB for 5 min |
| Disk writes | `instance/disk/write_ops_count` | `VolumeWriteOps` (root volume) | above 1000 ops/s for 5 min |
| Network in | `instance/network/received_bytes_count` | `NetworkIn` | above 1 Mbit/s for 5 min |
| Health | `instance/uptime` | `StatusCheckFailed` | no data for 5 min, or a failed check |

The thresholds are module defaults; `observability.thresholds` in the project
configuration overrides any of them. The dashboard is `<prefix> hosts` in
Cloud Monitoring and `<prefix>-hosts` in CloudWatch, one chart per row above
with the threshold drawn across.

Three more alerts come from the journal rather than from metrics:

- **A container died**: `docker-events.service` records every container exit;
  an exit code other than 0 raises an alert naming the instance, the
  container and the code. Code 0 is a planned stop and is ignored, so a deploy
  is silent.
- **HTTP 5xx**: a request log line from ui, history or fetcher with
  `status >= 500` raises an alert naming the container, the instance and the
  path. It needs the JSON request logs, so an image without them never fires.
- **Budget**: 100 % of `clouds.<cloud>.budget_usd` spent in the month. On
  GCP the budget lives on `clouds.gcp.billing_account`, and applying it needs
  a costs-manager role on that account; without the field no budget is
  created.

Everything goes to `observability.alert_email`. GCP mails it straight away;
**AWS first sends an SNS subscription confirmation, and nothing arrives until
that link is clicked.**

On GCP the alerts and the dashboard select VMs by the `application` and
`environment` labels, so a new VM is covered as soon as it exists. CloudWatch
has no such selector: alarms are per instance and, for containers, per
instance and container name, so a new Compose service on AWS means a new
entry in the alerting module's `containers_by_role`.

## Rolling it out

1. `terraform apply` — the IAM grants and the log group must exist before an
   agent starts; a GCP binding can take a minute to become effective.
2. `ansible-playbook oilscope.platform.observability` — agents on every host,
   containers untouched.
3. `ansible-playbook oilscope.platform.deploy_workloads` — the Docker daemon
   configuration, the journal settings and `docker-events.service`.
4. The logging driver is fixed when a container is created, so a container
   that already exists keeps `json-file` until it is recreated. The next image
   change does that; to do it sooner, remove the container
   (`docker rm -f petroscope-history-1`) and run the workload's playbook again.

Check a host with `docker inspect --format '{{.HostConfig.LogConfig.Type}}'
<container>` (expect `journald`) and `journalctl CONTAINER_NAME=<container>
-o cat` (expect one JSON document per line). On GCP the VM's page in the
console shows the Ops Agent as installed once the first entries arrive.

## Cost of running it

The Ops Agent's metrics subagent takes about 100 MB of memory. On a host that
cannot spare it — `tiny` sizes with PostgreSQL alongside — set
`observability_agent_gcp_metrics_enabled: false` for that host; logs keep
flowing. Fluent Bit alone needs a few tens of megabytes. Cloud Logging's
free allowance of 50 GB per project per month is far beyond what four hosts
produce; if kernel or apt noise ever matters, the receiver can drop units with
an `exclude_logs` processor.
