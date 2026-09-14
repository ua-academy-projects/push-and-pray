locals {
  cpu_enabled       = var.monitoring.enabled && var.monitoring.cpu.enabled && length(var.vms) > 0
  health_enabled    = var.monitoring.enabled && var.monitoring.vm_health.enabled && length(var.vms) > 0
  lifecycle_enabled = var.monitoring.enabled && var.monitoring.lifecycle.enabled && length(var.monitoring.lifecycle.notify_states) > 0 && length(var.vms) > 0
  http_5xx_ui_vms = var.monitoring.enabled && var.monitoring.http_5xx.enabled ? {
    for name, vm in var.vms : name => vm if vm.role == "ui"
  } : {}
  http_5xx_enabled = length(local.http_5xx_ui_vms) > 0
  enabled          = local.cpu_enabled || local.health_enabled || local.lifecycle_enabled || local.http_5xx_enabled
  cpu_vms          = local.cpu_enabled ? var.vms : {}
  health_vms       = local.health_enabled ? var.vms : {}
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

resource "aws_cloudwatch_log_group" "http_5xx" {
  for_each = local.http_5xx_ui_vms

  name              = "${var.resource_prefix}-traefik-access"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  for_each = local.http_5xx_ui_vms

  name           = "${var.resource_prefix}-traefik-http-5xx"
  pattern        = "{ $.DownstreamStatus >= 500 && $.DownstreamStatus < 600 }"
  log_group_name = aws_cloudwatch_log_group.http_5xx[each.key].name

  metric_transformation {
    name      = "HTTP5xxCount"
    namespace = "${var.resource_prefix}/Traefik"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_iam_role_policy" "http_log_writer" {
  for_each = local.http_5xx_ui_vms

  name = "${var.resource_prefix}-traefik-log-writer"
  role = each.value.iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PublishTraefikAccessLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
      ]
      Resource = [
        aws_cloudwatch_log_group.http_5xx[each.key].arn,
        "${aws_cloudwatch_log_group.http_5xx[each.key].arn}:*",
      ]
    }]
  })
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  for_each = local.http_5xx_ui_vms

  alarm_name          = "${each.value.name}-http-5xx"
  alarm_description   = "At least ${var.monitoring.http_5xx.threshold_count} HTTP 5xx responses in ${var.monitoring.http_5xx.duration_minutes} minutes"
  namespace           = "${var.resource_prefix}/Traefik"
  metric_name         = "HTTP5xxCount"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.monitoring.http_5xx.threshold_count
  period              = var.monitoring.http_5xx.duration_minutes * 60
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.monitoring[0].arn]
  tags                = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.http_5xx]
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = local.cpu_vms

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

resource "aws_cloudwatch_metric_alarm" "vm_health" {
  for_each = local.health_vms

  alarm_name          = "${each.value.name}-status-check-failed"
  alarm_description   = "EC2 instance or system status check failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 5
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.monitoring[0].arn]

  dimensions = {
    InstanceId = each.value.instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "lifecycle" {
  count = local.lifecycle_enabled ? 1 : 0

  name        = "${var.resource_prefix}-vm-lifecycle"
  description = "Notify when a Terraform-managed EC2 instance enters a configured lifecycle state"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      instance-id = sort([for vm in values(var.vms) : vm.instance_id])
      state       = sort(tolist(var.monitoring.lifecycle.notify_states))
    }
  })

  tags = var.tags
}

resource "aws_sns_topic_policy" "monitoring" {
  count = local.lifecycle_enabled ? 1 : 0

  arn = aws_sns_topic.monitoring[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeLifecyclePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.monitoring[0].arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.lifecycle[0].arn
        }
      }
    }]
  })
}

resource "aws_cloudwatch_event_target" "lifecycle_sns" {
  count = local.lifecycle_enabled ? 1 : 0

  target_id = "MonitoringSns"
  rule      = aws_cloudwatch_event_rule.lifecycle[0].name
  arn       = aws_sns_topic.monitoring[0].arn

  depends_on = [aws_sns_topic_policy.monitoring]
}

resource "aws_cloudwatch_dashboard" "cpu" {
  count = local.enabled ? 1 : 0

  dashboard_name = "${var.resource_prefix}-cpu"
  dashboard_body = jsonencode({
    widgets = concat(local.cpu_enabled ? [{
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
      }] : [], local.health_enabled ? [{
      type   = "metric"
      x      = 0
      y      = local.cpu_enabled ? 8 : 0
      width  = 24
      height = 8
      properties = {
        title  = "EC2 status check failures"
        view   = "timeSeries"
        region = data.aws_region.current[0].region
        stat   = "Maximum"
        period = 60
        yAxis = {
          left = { min = 0, max = 1 }
        }
        metrics = [
          for vm in values(var.vms) : [
            "AWS/EC2", "StatusCheckFailed", "InstanceId", vm.instance_id,
            { label = vm.name },
          ]
        ]
      }
      }] : [], local.http_5xx_enabled ? [{
      type   = "metric"
      x      = 0
      y      = (local.cpu_enabled ? 8 : 0) + (local.health_enabled ? 8 : 0)
      width  = 24
      height = 8
      properties = {
        title  = "Traefik HTTP 5xx responses"
        view   = "timeSeries"
        region = data.aws_region.current[0].region
        stat   = "Sum"
        period = 60
        metrics = [[
          "${var.resource_prefix}/Traefik", "HTTP5xxCount",
          { label = local.http_5xx_ui_vms[keys(local.http_5xx_ui_vms)[0]].name },
        ]]
      }
    }] : [])
  })
}

data "aws_region" "current" {
  count = local.enabled ? 1 : 0
}
