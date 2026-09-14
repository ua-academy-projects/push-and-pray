# Observability agent

Installs the agent that ships this host's journal and host metrics to the
cloud the host runs on, and configures it so container output arrives as
structured log entries with the application's own severity.

| Cloud | Logs | Host metrics |
| --- | --- | --- |
| `gcp` | Ops Agent, `systemd_journald` receiver → Cloud Logging | Ops Agent, built-in `hostmetrics` → Cloud Monitoring |
| `aws` | Fluent Bit, `systemd` input → CloudWatch Logs | CloudWatch agent → CloudWatch Metrics |

One cloud needs two packages because the CloudWatch agent cannot read the
journal. The cloud comes from `oilscope_cloud`, which the dynamic inventory
stamps on every host; one task file per cloud, selected by name, so adding a
provider adds a file and not a branch.

## What is collected

Everything the journal holds, because that is where every process on the host
logs:

- stdout and stderr of every container: `docker_engine` sets the `journald`
  logging driver, and the Compose project and service names ride along as
  `COM_DOCKER_COMPOSE_PROJECT` and `COM_DOCKER_COMPOSE_SERVICE`;
- `docker.service` itself: pulls, failed starts, restarts;
- `ssh.service`, `sudo` and PAM — the bastion's reason to run the agent;
- the kernel, which is where an OOM kill is recorded;
- systemd, cloud-init, unattended-upgrades and apt.

Host metrics: CPU, memory, swap, disk usage and network. On AWS only what EC2
does not already report is collected (memory, swap, disk usage).

## How container lines are handled

Docker stamps every stderr line `PRIORITY=3`, which Cloud Logging would show
as `ERROR` — and the applications log to stderr. The agent therefore parses
each container line as JSON, moves its `level` into the entry's severity, and
normalises `msg` to `message`. Lines that are not JSON (Postgres, sshd, the
kernel) pass through untouched. The applications are expected to emit one JSON
document per line with `level` and `message` or `msg` keys; a plain-text line
still arrives, just without a severity of its own.

On AWS the same parse runs in Fluent Bit so Logs Insights discovers the keys.

## Requirements

- The identity attached to the VM must be allowed to write. Terraform grants
  `roles/logging.logWriter` and `roles/monitoring.metricWriter` on GCP, and an
  inline policy for the environment's log group plus `cloudwatch:PutMetricData`
  on AWS, to every workload identity and to the bastion's.
- Outbound access to `packages.cloud.google.com` or `packages.fluentbit.io`
  and `amazoncloudwatch-agent.s3.amazonaws.com`, and to the cloud's logging
  API. The workload subnets have NAT and, on GCP, Private Google Access.
- On AWS the log group must exist; Terraform creates
  `/<name_prefix>-<environment>/journald` and the role derives the same name
  from the project configuration, so the two cannot drift apart.

Privilege escalation is required; the role requests it per task. Facts are
gathered by the role itself when the play did not, so it works from the
bastion bootstrap play too.

## Role variables

- `observability_agent_cloud`: which cloud this host is on. Defaults to
  `oilscope_cloud`; a cloud without an `install-<cloud>.yml` is refused.
- `observability_agent_config_path`: the project configuration JSON. Read on
  AWS for the region and the log group name; unused on GCP.
- `observability_agent_gcp_metrics_enabled`: whether the Ops Agent runs its
  metrics subagent, which costs about 100 MB of memory. Enabled by default;
  disable it on a host that cannot spare that, logs keep flowing.
- `observability_agent_aws_cloudwatch_metrics_enabled`: whether the CloudWatch
  agent is installed at all. Enabled by default.
- `observability_agent_aws_cloudwatch_interval_seconds`: metrics interval;
  defaults to 60.
- `observability_agent_severity_map` (in `vars/`): application log levels and
  the Cloud Logging severity each becomes.
- Repository, key, package, service and path settings for each agent; see
  `defaults/main.yml`.

## Finding the logs

Logs Explorer:

```text
logName="projects/<project_id>/logs/journald"
jsonPayload.CONTAINER_NAME="petroscope-history-1"
severity>=WARNING
```

CloudWatch Logs Insights, log group `/<name_prefix>-<environment>/journald`:

```text
fields @timestamp, message, level
| filter CONTAINER_NAME = "petroscope-history-1" and level = "ERROR"
```

## Dependencies

None declared. `host_baseline` sets the journal's size and rate limits and
`docker_engine` points containers at the journal; the deployment playbooks
apply both alongside this role.

## Example playbook

```yaml
---
- name: Ship host logs and metrics
  hosts: all
  become: true
  roles:
    - role: oilscope.platform.observability_agent
      vars:
        observability_agent_config_path: "{{ project_config_path }}"
```

## License

GPL-2.0-or-later
