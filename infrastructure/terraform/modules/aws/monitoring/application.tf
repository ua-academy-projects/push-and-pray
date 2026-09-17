locals {
  application_catalog = jsondecode(file("${path.module}/../../../monitoring-metrics.json"))
  application_signals = merge({}, [for name, vm in local.workload_vms : {
    for metric, definition in local.application_catalog : "${name}-${metric}" => {
      name      = name
      metric    = metric
      threshold = try(local.settings[definition.setting], definition.threshold)
    } if contains(definition.roles, var.config.vms[name].role)
  }]...)
  collector_configurations = { for name, vm in local.workload_vms : name => {
    cloud       = "aws"
    vm_key      = name
    namespace   = local.application_namespace
    instance_id = vm.instance_id

  } if local.application_enabled }
}
output "collector_configurations" {
  value = local.collector_configurations
}
resource "aws_cloudwatch_metric_alarm" "application" {
  for_each            = local.application_enabled && local.alarms_enabled ? local.application_signals : {}
  alarm_name          = "${local.resource_prefix}-${each.key}"
  namespace           = local.application_namespace
  metric_name         = each.value.metric
  dimensions          = { VMKey = each.value.name }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.threshold
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.common_labels
}
locals {
  database_signals = {
    CPUUtilization      = { threshold = local.settings.database_cpu_threshold_percent, comparison = "GreaterThanOrEqualToThreshold" }
    FreeStorageSpace    = { threshold = local.settings.database_free_storage_bytes, comparison = "LessThanThreshold" }
    DatabaseConnections = { threshold = local.settings.database_connections_threshold, comparison = "GreaterThanOrEqualToThreshold" }
  }
}
resource "aws_cloudwatch_metric_alarm" "database" {
  for_each            = local.database_enabled && local.alarms_enabled ? local.database_signals : {}
  alarm_name          = "${local.resource_prefix}-rds-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = each.key
  dimensions          = { DBInstanceIdentifier = var.database.id }
  statistic           = "Average"
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.common_labels
}
