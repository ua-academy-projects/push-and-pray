locals {
  enabled = var.monitoring.enabled && var.monitoring.cpu.enabled && length(var.vms) > 0
  vms     = local.enabled ? var.vms : {}
}

resource "aws_sns_topic" "monitoring" {
  count = local.enabled ? 1 : 0

  name = "${var.resource_prefix}-monitoring"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = local.enabled ? 1 : 0

  topic_arn = aws_sns_topic.monitoring[0].arn
  protocol  = "email"
  endpoint  = var.monitoring.notification_email
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = local.vms

  alarm_name          = "${each.value.name}-high-cpu"
  alarm_description   = "CPU above ${var.monitoring.cpu.threshold_percent}% for ${var.monitoring.cpu.duration_minutes} minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.monitoring.cpu.threshold_percent
  period              = 60
  evaluation_periods  = var.monitoring.cpu.duration_minutes
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.monitoring[0].arn]

  dimensions = {
    InstanceId = each.value.instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_dashboard" "cpu" {
  count = local.enabled ? 1 : 0

  dashboard_name = "${var.resource_prefix}-cpu"
  dashboard_body = jsonencode({
    widgets = [{
      type   = "metric"
      x      = 0
      y      = 0
      width  = 24
      height = 8
      properties = {
        title  = "EC2 CPU utilization"
        view   = "timeSeries"
        region = data.aws_region.current[0].region
        stat   = "Average"
        period = 60
        yAxis = {
          left = { min = 0, max = 100 }
        }
        metrics = [
          for vm in values(var.vms) : [
            "AWS/EC2", "CPUUtilization", "InstanceId", vm.instance_id,
            { label = vm.name },
          ]
        ]
      }
    }]
  })
}

data "aws_region" "current" {
  count = local.enabled ? 1 : 0
}
