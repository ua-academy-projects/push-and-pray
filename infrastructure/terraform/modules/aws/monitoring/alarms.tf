resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = var.instance_ids

  alarm_name          = "${var.resource_prefix}-${each.key}-high-cpu"
  alarm_description   = "EC2 CPU utilization is above ${var.cpu.threshold_percent}% for ${var.cpu.duration_seconds} seconds."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = local.period_seconds
  statistic           = "Average"
  threshold           = var.cpu.threshold_percent
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    InstanceId = each.value
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "instance_status_failed" {
  for_each = var.instance_ids

  alarm_name          = "${var.resource_prefix}-${each.key}-instance-status-failed"
  alarm_description   = "EC2 instance or system status check failed."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = local.period_seconds
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    InstanceId = each.value
  }

  tags = var.tags
}
