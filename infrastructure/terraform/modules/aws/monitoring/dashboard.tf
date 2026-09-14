locals {
  dashboard_vm_names = sort(keys(var.vms))
  dashboard_colors = [
    "#1f77b4",
    "#ff7f0e",
    "#2ca02c",
    "#d62728",
    "#9467bd",
    "#8c564b",
    "#e377c2",
    "#7f7f7f",
    "#bcbd22",
    "#17becf",
  ]
  dashboard_vm_colors = {
    for index, name in local.dashboard_vm_names :
    name => local.dashboard_colors[index % length(local.dashboard_colors)]
  }
  dashboard_signal_order = concat(
    ["cpu", "status"],
    local.agent_enabled ? ["memory", "disk"] : []
  )
  dashboard_signal_titles = {
    cpu    = "VM CPU utilization (%)"
    status = "VM status check failures"
    memory = "VM memory used (%)"
    disk   = "VM root disk used (%)"
  }
  dashboard_charts = concat(
    [for signal_name in local.dashboard_signal_order : {
      title = local.dashboard_signal_titles[signal_name]
      metrics = [for name in local.dashboard_vm_names : concat(
        [local.signals[signal_name].namespace, local.signals[signal_name].metric],
        flatten([for dimension_name, dimension_value in merge(
          { InstanceId = var.vms[name].instance_id },
          signal_name == "disk" ? { path = "/", fstype = local.settings.disk_fstype } : {}
        ) : [dimension_name, dimension_value]]),
        [{ label = name, color = local.dashboard_vm_colors[name] }]
      )]
      stat   = local.signals[signal_name].stat
      period = local.signals[signal_name].period
    }],
    [for metric in ["NetworkIn", "NetworkOut"] : {
      title = "VM ${metric == "NetworkIn" ? "network received" : "network sent"} (bytes/5 min)"
      metrics = [for name in local.dashboard_vm_names : [
        "AWS/EC2", metric, "InstanceId", var.vms[name].instance_id,
        { label = name, color = local.dashboard_vm_colors[name] }
      ]]
      stat   = "Sum"
      period = 300
    }],
    local.logs_enabled ? [{
      title = "HTTP errors (count/5 min)"
      metrics = [for index, metric in sort(keys(local.http_filters)) : [
        local.http_namespace, metric,
        { label = metric, color = local.dashboard_colors[index] }
      ]]
      stat   = "Sum"
      period = 300
    }] : [],
    local.synthetics_enabled ? [for metric in ["SuccessPercent", "Duration"] : {
      title = "HTTPS ${metric}"
      metrics = [[
        "CloudWatchSynthetics", metric, "CanaryName", local.canary_name,
        { label = local.canary_name }
      ]]
      stat   = "Average"
      period = local.settings.synthetics.period_minutes * 60
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
      type   = "alarm"
      x      = 0
      y      = ceil(length(local.dashboard_charts) / 2) * 6
      width  = 24
      height = 6
      properties = {
        title  = "Operational alarms"
        alarms = concat([for a in aws_cloudwatch_metric_alarm.vm : a.arn], [for a in aws_cloudwatch_metric_alarm.http : a.arn], aws_cloudwatch_metric_alarm.synthetic[*].arn)
      }
    }] : [])
  })
}
