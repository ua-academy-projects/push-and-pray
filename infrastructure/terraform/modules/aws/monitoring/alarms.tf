resource "aws_cloudwatch_metric_alarm" "vm" {
  for_each            = local.alarms_enabled ? local.vm_signals : {}
  alarm_name          = "${local.resource_prefix}-${each.key}"
  alarm_description   = "${each.value.vm_name}: ${each.value.signal}. Check EC2 status, agent telemetry and workload logs. Missing-agent/status alarms assume always-on VMs."
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = each.value.stat
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  period              = each.value.period
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.common_labels
}

resource "aws_cloudwatch_metric_alarm" "http" {
  for_each            = local.alarms_enabled && local.logs_enabled ? local.http_filters : {}
  alarm_name          = "${local.resource_prefix}-${each.key}"
  alarm_description   = "New Traefik error responses. Check access logs and application dependencies; an empty event stream is not an availability check."
  namespace           = local.http_namespace
  metric_name         = each.key
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = local.settings.http_error_threshold
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.common_labels
}

resource "aws_cloudwatch_metric_alarm" "synthetic" {
  count               = local.alarms_enabled && local.synthetics_enabled ? 1 : 0
  alarm_name          = "${local.resource_prefix}-health"
  alarm_description   = "Public HTTPS health check failed or stopped publishing. Check DNS, TLS, Traefik, History and database connectivity."
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  dimensions          = { CanaryName = aws_synthetics_canary.health[0].name }
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = 100
  period              = local.settings.synthetics.period_minutes * 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.common_labels
}
