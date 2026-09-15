# GCP alerting module

Turns the monitoring module's metric table and the journal into e-mail: one
channel, one policy per watched metric, two log-matched policies, and a
budget on the billing account.

## Resources

| Resource | Purpose |
| --- | --- |
| `google_monitoring_notification_channel` | The e-mail address; no confirmation step on GCP |
| `google_monitoring_alert_policy.metric` | Per metric: above the threshold for five minutes, or - for `uptime` - no data for five minutes, which is a VM that is down |
| `google_monitoring_alert_policy.container_died` | A `docker-events` line with a non-zero exit code; the mail names the instance, the container and the code |
| `google_monitoring_alert_policy.http_5xx` | A ui, history or fetcher request log with status 500 or more; the mail names the container, the instance and the path |
| `google_project_service` | Enables `billingbudgets.googleapis.com`, off in a fresh project |
| `google_billing_budget` | Monthly budget on the billing account, filtered to this project, notifying the channel at 100 % |

Log-matched policies notify at most once per five minutes per policy and
close after thirty minutes without a new match. The container policy skips
exit code 0 on purpose: a deploy stops containers with SIGTERM and every
service in the project exits cleanly on it.

## Inputs

| Name | Description |
| --- | --- |
| `project_id`, `resource_prefix` | Where the policies live and how they are named |
| `email` | Recipient of everything |
| `metrics` | `module.monitoring.metrics` |
| `log_name` | `module.logging.log_name` |
| `budget_usd`, `billing_account` | Both needed for the budget; leave either null to skip it |

The identity running Terraform needs `roles/billing.costsManager` or
`roles/billing.admin` on the billing account for the budget to apply.

## Outputs

| Name | Description |
| --- | --- |
| `notification_channel_id` | The e-mail channel |

## Usage

```hcl
module "alerting" {
  source = "./modules/alerting"
  count  = local.is_active ? 1 : 0

  project_id      = local.profile.project_id
  resource_prefix = local.resource_prefix
  email           = var.config.observability.alert_email
  metrics         = module.monitoring[0].metrics
  log_name        = module.logging[0].log_name
  budget_usd      = try(local.profile.budget_usd, null)
  billing_account = try(local.profile.billing_account, null)
}
```

## License

GPL-2.0-or-later
