resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = var.instance_ids

  alarm_name          = "${var.resource_prefix}-${each.key}-high-cpu"
  alarm_description   = "EC2 CPU utilization is above ${var.settings.cpu.threshold_percent}% for ${var.settings.cpu.duration_seconds} seconds."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = local.period_seconds
  statistic           = "Average"
  threshold           = var.settings.cpu.threshold_percent
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    InstanceId = each.value
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "high_disk" {
  for_each = var.instance_ids

  alarm_name          = "${var.resource_prefix}-${each.key}-high-disk"
  alarm_description   = "EC2 root disk utilization is above ${var.settings.disk.threshold_percent}% for ${var.settings.disk.duration_seconds} seconds."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.disk_evaluation_periods
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = local.period_seconds
  statistic           = "Average"
  threshold           = var.settings.disk.threshold_percent
  # The agent is installed by Ansible after Terraform creates this alarm.
  # Do not page merely because that first agent run has not happened yet.
  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_sns_topic.alarms.arn]
  ok_actions         = [aws_sns_topic.alarms.arn]

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

resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  count = var.managed_database_enabled ? 1 : 0

  alarm_name          = "${var.resource_prefix}-postgres-high-cpu"
  alarm_description   = "RDS PostgreSQL CPU utilization is above ${var.settings.cpu.threshold_percent}% for ${var.settings.cpu.duration_seconds} seconds."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = local.period_seconds
  statistic           = "Average"
  threshold           = var.settings.cpu.threshold_percent
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.database_instance_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_low_free_storage" {
  count = var.managed_database_enabled ? 1 : 0

  alarm_name          = "${var.resource_prefix}-postgres-low-free-storage"
  alarm_description   = "RDS PostgreSQL has less than 2 GiB of free storage."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = local.period_seconds
  statistic           = "Average"
  threshold           = 2147483648
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.database_instance_identifier
  }

  tags = var.tags
}
