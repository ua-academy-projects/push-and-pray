resource "aws_cloudwatch_log_group" "docker" {
  count = var.settings.logs.enabled ? 1 : 0

  name              = local.log_group_name
  retention_in_days = 30
  tags              = var.tags
}

# Docker's standard JSON logger records Python's level name in the message.
# CloudWatch Logs filter patterns are not PCRE, so the cross-cloud PCRE setting
# cannot be reused here; ERROR is the portable log-level marker.
resource "aws_cloudwatch_log_metric_filter" "container_errors" {
  count = var.settings.logs.enabled ? 1 : 0

  name           = "${var.resource_prefix}-container-errors"
  log_group_name = aws_cloudwatch_log_group.docker[0].name
  pattern        = "ERROR"

  metric_transformation {
    name          = "ContainerErrors"
    namespace     = "${var.resource_prefix}/Application"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "container_errors" {
  count = var.settings.logs.enabled ? 1 : 0

  alarm_name          = "${var.resource_prefix}-container-errors"
  alarm_description   = "A Docker container emitted an ERROR log entry."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ContainerErrors"
  namespace           = "${var.resource_prefix}/Application"
  period              = local.period_seconds
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.container_errors]
}
