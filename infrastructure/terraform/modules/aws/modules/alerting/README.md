# AWS alerting module

Turns the monitoring module's metric table and the log group into e-mail:
one topic, one alarm per instance and watched metric, log-filtered alarms for
crashed containers and HTTP 5xx, and a monthly budget.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_sns_topic`, `aws_sns_topic_subscription` | The e-mail address. **SNS mails a confirmation link first; nothing arrives until it is clicked** |
| `aws_cloudwatch_metric_alarm.metric` | Per instance and metric: past the threshold for five minutes; the health check also alarms on missing data, which is a stopped instance |
| `aws_cloudwatch_log_metric_filter` + `aws_cloudwatch_metric_alarm.container_died` | Per instance and container: a `docker-events` line with a non-zero exit code. The alarm is named after both, because CloudWatch cannot lift a name out of a log line into a notification |
| `aws_cloudwatch_log_metric_filter` + `aws_cloudwatch_metric_alarm.http_5xx` | Per service (ui, history, fetcher): a request log with status 500 or more |
| `aws_budgets_budget` | Monthly cost budget, mailing the address directly at 100 % |

The container filters match on `instance`, a field Fluent Bit adds from the
inventory hostname - an EC2 host's own hostname is its address, not its name.
Exit code 0 is skipped on purpose: a deploy stops containers with SIGTERM and
every service in the project exits cleanly on it.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every name |
| `email` | Recipient of everything |
| `metrics` | `module.monitoring.metrics` |
| `instances` | Per instance name: `id`, `volume_id`, `role`, `name` |
| `containers_by_role` | Which container names each role runs; defaults to the project's Compose names |
| `log_group_name` | `module.logging.log_group_name` |
| `budget_usd` | Monthly limit; null skips the budget |
| `tags` | Tags for the topic, alarms and budget |

## Outputs

| Name | Description |
| --- | --- |
| `topic_arn` | The topic every alarm publishes to |

## Usage

```hcl
module "alerting" {
  source = "./modules/alerting"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  email           = var.config.observability.alert_email
  metrics         = module.monitoring[0].metrics
  instances       = local.instances
  log_group_name  = module.logging[0].log_group_name
  budget_usd      = try(local.profile.budget_usd, null)
  tags            = local.common_tags
}
```

## License

GPL-2.0-or-later
