resource "aws_sns_topic" "alerts" {
  name = "${local.resource_prefix}-alerts"

  tags = merge(var.config.common_labels, {
    environment = var.config.environment
    managed_by  = "terraform"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.config.monitoring.alert_email
}

resource "aws_sns_topic" "availability" {
  count  = local.region == "us-east-1" ? 0 : 1
  region = "us-east-1"
  name   = "${local.resource_prefix}-availability-alerts"
}

resource "aws_sns_topic_subscription" "availability_email" {
  count = local.region == "us-east-1" ? 0 : 1

  region    = "us-east-1"
  topic_arn = aws_sns_topic.availability[0].arn
  protocol  = "email"
  endpoint  = var.config.monitoring.alert_email
}

resource "aws_cloudwatch_metric_alarm" "vm" {
  for_each = local.vm_alarms

  alarm_name          = "${local.resource_prefix}-${replace(each.key, "/", "-")}-high"
  alarm_description   = "${each.value.vm_name} ${each.value.metric_name} exceeds the configured threshold."
  namespace           = local.namespace
  metric_name         = each.value.metric_name
  dimensions          = { InstanceId = each.value.instance_id }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.threshold
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  statistic           = "Average"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ui_availability" {
  for_each = aws_route53_health_check.ui

  region              = "us-east-1"
  alarm_name          = "${local.resource_prefix}-ui-unavailable"
  alarm_description   = "The public UI health endpoint is unavailable."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = each.value.id }
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  statistic           = "Minimum"
  treat_missing_data  = "breaching"
  alarm_actions       = [local.availability_alarm_arn]
  ok_actions          = [local.availability_alarm_arn]
}

resource "aws_cloudwatch_metric_alarm" "redis" {
  alarm_name          = "${local.resource_prefix}-redis-unavailable"
  alarm_description   = "The Redis exporter reports that Redis is unavailable."
  namespace           = local.namespace
  metric_name         = "redis_up"
  dimensions          = { job = "redis" }
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  statistic           = "Minimum"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${local.resource_prefix}-database-cpu-high"
  alarm_description   = "RDS CPU utilization exceeds the configured threshold."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = local.database_identifier }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.config.monitoring.thresholds.cpu_percent
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  statistic           = "Average"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  alarm_name          = "${local.resource_prefix}-database-storage-low"
  alarm_description   = "RDS free storage is below 20 percent of allocated storage."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = local.database_identifier }
  comparison_operator = "LessThanThreshold"
  threshold           = var.config.services.database.aws.allocated_storage_gb * 1024 * 1024 * 1024 * 0.2
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  statistic           = "Average"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
