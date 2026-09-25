# Infrastructure monitoring

The shared `monitoring` JSON object controls monitoring in both clouds:

- `metrics_interval_seconds` controls VM and application scrape frequency;
- `log_retention_days` controls centralized log retention;
- `alert_email` receives alerts;
- `ui_health_path` is checked over public HTTPS;
- `thresholds` defines CPU, memory, and disk warning levels.

## AWS

Terraform creates CloudWatch log groups, VM and RDS alarms, an SNS topic, a
Route 53 HTTPS health check, and the `oilscope-<environment>-overview`
dashboard. Ansible installs the CloudWatch Agent on every VM. On `infra`, the
agent also converts selected RabbitMQ and Redis Prometheus metrics into the
`OilScope/<environment>` CloudWatch namespace.

AWS sends a confirmation message to `monitoring.alert_email` after the first
apply. Alerts are not delivered until the SNS subscription is confirmed.

## GCP

Terraform creates an uptime check, VM and Cloud SQL alert policies, an email
notification channel, and an `oilscope-<environment> overview` dashboard.
Ansible installs the Ops Agent on every VM and enables a Prometheus receiver on
`infra` for RabbitMQ and Redis.

The GCP bootstrap identity needs `roles/monitoring.editor`, and the Monitoring
and Logging APIs must be enabled before Terraform runs.

## Application metrics

The initial dashboard keeps a small set of useful signals:

- RabbitMQ connections, consumers, ready messages, and unacknowledged messages;
- Redis availability, connected clients, memory use, keyspace hits, and misses.

Exporter ports listen only on `127.0.0.1` of the `infra` VM and are not exposed
through cloud firewall rules.

Route 53 health checks, CloudWatch custom metrics, logs, and provider-side log
or metric ingestion can incur usage charges.
