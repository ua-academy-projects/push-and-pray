data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "alerts" {
  name = "${var.resource_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = var.instances

  role       = each.value.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.resource_prefix}/application"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  name           = "${var.resource_prefix}-http-5xx"
  log_group_name = aws_cloudwatch_log_group.application.name
  pattern        = "{ $.event = \"http_access\" && $.status >= 500 && $.status < 600 }"

  metric_transformation {
    name          = "HTTP5xxCount"
    namespace     = "OilScope/Application"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  for_each = var.instances

  alarm_name          = "${var.resource_prefix}-aws-${each.key}-status-check-failed"
  alarm_description   = "Kickoff: EC2 status check failed. Closure: status returned to OK. Dashboard: ${var.resource_prefix}-aws"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  dimensions          = { InstanceId = each.value.instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.instances

  alarm_name          = "${var.resource_prefix}-aws-${each.key}-cpu-high"
  alarm_description   = "Kickoff: average CPU is above 80% for 5 minutes. Closure: CPU returned below threshold. Dashboard: ${var.resource_prefix}-aws"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions          = { InstanceId = each.value.instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = var.instances

  alarm_name          = "${var.resource_prefix}-aws-${each.key}-memory-high"
  alarm_description   = "Kickoff: memory usage is above 80% for 5 minutes. Closure: memory returned below threshold. Dashboard: ${var.resource_prefix}-aws"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions          = { InstanceId = each.value.instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  for_each = var.instances

  alarm_name          = "${var.resource_prefix}-aws-${each.key}-disk-high"
  alarm_description   = "Kickoff: root disk usage is above 80% for 10 minutes. Closure: disk usage returned below threshold. Dashboard: ${var.resource_prefix}-aws"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    InstanceId = each.value.instance_id
    path       = "/"
    fstype     = "ext4"
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.resource_prefix}-aws-http-5xx"
  alarm_description   = "Kickoff: structured HTTP 5xx threshold reached. Closure: no 5xx in the next period. Dashboard: ${var.resource_prefix}-aws"
  namespace           = "OilScope/Application"
  metric_name         = "HTTP5xxCount"
  statistic           = "Sum"
  period              = var.http_5xx_window_seconds
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.http_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.http_5xx]
}

resource "aws_cloudwatch_metric_alarm" "database_cpu_high" {
  count = var.database_enabled ? 1 : 0

  alarm_name          = "${var.resource_prefix}-aws-database-cpu-high"
  alarm_description   = "Kickoff: RDS CPU is above 80% for 5 minutes. Closure: CPU returned below threshold."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions          = { DBInstanceIdentifier = var.database_identifier }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_storage_low" {
  count = var.database_enabled ? 1 : 0

  alarm_name          = "${var.resource_prefix}-aws-database-storage-low"
  alarm_description   = "Kickoff: RDS free storage is below 2 GiB for 10 minutes. Closure: free storage recovered."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  dimensions          = { DBInstanceIdentifier = var.database_identifier }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.resource_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = toset([50, 80, 100])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
