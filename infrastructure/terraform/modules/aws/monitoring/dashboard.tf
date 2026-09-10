locals {
  dashboard_charts = concat(
    [for key, signal in local.vm_signals : {
      title   = "${signal.vm_name}: ${signal.signal}"
      metrics = [concat([signal.namespace, signal.metric], flatten([for name, value in signal.dimensions : [name, value]]))]
      stat    = signal.stat
      period  = signal.period
    } if signal.signal != "agent_missing"],
    [for metric in ["NetworkIn", "NetworkOut"] : {
      title   = metric
      metrics = [for name, vm in var.vms : ["AWS/EC2", metric, "InstanceId", vm.instance_id, { label = name }]]
      stat    = "Sum"
      period  = 300
    }],
    local.logs_enabled ? [for metric in keys(local.http_filters) : {
      title = metric, metrics = [[local.http_namespace, metric]], stat = "Sum", period = 300
    }] : [],
    local.synthetics_enabled ? [for metric in ["SuccessPercent", "Duration"] : {
      title = "HTTPS ${metric}", metrics = [["CloudWatchSynthetics", metric, "CanaryName", local.canary_name]], stat = "Average", period = local.settings.synthetics.period_minutes * 60
    }] : []
  )
}
resource "aws_cloudwatch_dashboard" "operations" {
  count          = local.enabled && local.settings.dashboard_enabled ? 1 : 0
  dashboard_name = "${local.resource_prefix}-operations"
  dashboard_body = jsonencode({
    widgets = concat([for index, chart in local.dashboard_charts : {
      type       = "metric"
      x          = (index % 2) * 12
      y          = floor(index / 2) * 6
      width      = 12
      height     = 6
      properties = merge(chart, { region = local.region, view = "timeSeries" })
      }], local.alarms_enabled ? [{
      type       = "alarm", x = 0, y = ceil(length(local.dashboard_charts) / 2) * 6, width = 24, height = 6
      properties = { title = "Operational alarms", alarms = concat([for a in aws_cloudwatch_metric_alarm.vm : a.arn], [for a in aws_cloudwatch_metric_alarm.http : a.arn], aws_cloudwatch_metric_alarm.synthetic[*].arn) }
    }] : [])
  })
}
