# AWS alerting module

Turns the monitoring module's metric table into e-mail: one topic, one alarm
per instance and watched metric, and a monthly budget.

What runs inside the cluster - pods restarting, services answering 5xx - is
not watched here: k3s runs containers through containerd, not Docker, so the
journal no longer names them. That belongs to Prometheus in the cluster.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_sns_topic`, `aws_sns_topic_subscription` | The e-mail address. **SNS mails a confirmation link first; nothing arrives until it is clicked** |
| `aws_cloudwatch_metric_alarm.metric` | Per instance and metric: past the threshold for five minutes; the health check also alarms on missing data, which is a stopped instance |
| `aws_budgets_budget` | Monthly cost budget, mailing the address directly at 100 % |

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every name |
| `email` | Recipient of everything |
| `metrics` | `module.monitoring.metrics` |
| `instances` | Per instance name: `id`, `volume_id`, `role`, `name` |
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
  budget_usd      = try(local.profile.budget_usd, null)
  tags            = local.common_tags
}
```

## License

GPL-2.0-or-later
