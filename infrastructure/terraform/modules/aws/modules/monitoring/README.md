# AWS monitoring module

Lets every instance role write metrics, defines which metrics matter, and
draws them on one dashboard. The metric table is the module's real product:
the alerting module builds one alarm per instance and entry from it and never
names a metric itself.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_iam_role_policy` | `cloudwatch:PutMetricData` in the `CWAgent` namespace, per role |
| `aws_cloudwatch_dashboard` | One chart per watched metric, every instance as a line, the threshold drawn across |

## Metrics

| Entry | Metric | Source | Default threshold |
| --- | --- | --- | --- |
| `cpu` | `AWS/EC2 CPUUtilization`, average | EC2 | 75 % |
| `memory` | `CWAgent mem_used`, average | CloudWatch agent | 1.5 GB |
| `disk_write` | `AWS/EBS VolumeWriteOps` on the root volume, sum per minute | EBS | 1000 ops/s × 60 |
| `network_in` | `AWS/EC2 NetworkIn`, sum per minute | EC2 | 1 Mbit/s × 60 |
| `health` | `AWS/EC2 StatusCheckFailed`, maximum | EC2 | 1, and missing data counts as failed |

CloudWatch reports sums per period, so the per-second thresholds shared with
GCP are scaled by the 60-second period here. CloudWatch also addresses a
series by instance or volume ID rather than by tag, which is why this module
takes the instance list that its GCP counterpart does without.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for the dashboard and policy names |
| `region` | Region the dashboard reads from |
| `identities` | IAM role name per instance name |
| `instances` | Per instance name: `id` and `volume_id` |
| `thresholds` | Optional overrides: `cpu_utilization`, `memory_used_gb`, `disk_write_ops_per_second`, `network_received_mbit_per_second` |
| `tags` | Tags for the dashboard |

## Outputs

| Name | Description |
| --- | --- |
| `metrics` | The table above, resolved: namespace, name, statistic, dimension, threshold, comparison and missing-data rule per entry |
| `dashboard_arn` | ARN of the dashboard |

## Usage

```hcl
module "monitoring" {
  source = "./modules/monitoring"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  region          = local.profile.region
  identities      = local.identities
  instances       = local.instances
  thresholds      = try(var.config.observability.thresholds, {})
  tags            = local.common_tags
}
```

## License

GPL-2.0-or-later
