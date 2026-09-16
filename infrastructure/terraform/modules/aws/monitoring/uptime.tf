resource "aws_route53_health_check" "ui" {
  count = var.settings.uptime.enabled ? 1 : 0

  fqdn              = var.uptime_hostname
  port              = 443
  type              = "HTTPS"
  resource_path     = var.settings.uptime.path
  request_interval  = 30
  failure_threshold = 3
  measure_latency   = true
  tags              = var.tags

  lifecycle {
    precondition {
      condition     = var.uptime_hostname != null && var.uptime_hostname != ""
      error_message = "Uptime monitoring is enabled, but no AWS UI hostname was found."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "ui_unavailable" {
  count = var.settings.uptime.enabled ? 1 : 0

  alarm_name          = "${var.resource_prefix}-ui-unavailable"
  alarm_description   = "The public UI HTTPS health check is unhealthy."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags

  dimensions = {
    HealthCheckId = aws_route53_health_check.ui[0].id
  }
}
