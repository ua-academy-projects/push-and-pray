resource "aws_sns_topic" "alerts" {
  for_each = local.vm_regions

  region = each.key
  name   = "${var.config.name_prefix}-${var.config.environment}-monitoring-alerts"
  tags   = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = local.vm_regions

  region    = each.key
  topic_arn = aws_sns_topic.alerts[each.key].arn
  protocol  = "email"
  endpoint  = var.config.monitoring.alert_email
}

resource "aws_cloudwatch_metric_alarm" "instance_health" {
  for_each = var.vms

  region              = var.config.locations[each.value.location].aws.region
  alarm_name          = "${each.value.name}-instance-health"
  alarm_description   = "EC2 status checks are failing or no health data is being reported."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Maximum"
  threshold           = 1
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts[var.config.locations[each.value.location].aws.region].arn]
  ok_actions          = [aws_sns_topic.alerts[var.config.locations[each.value.location].aws.region].arn]

  dimensions = {
    InstanceId = each.value.id
  }

  tags = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = var.vms

  region              = var.config.locations[each.value.location].aws.region
  alarm_name          = "${each.value.name}-high-cpu"
  alarm_description   = "Average EC2 CPU utilization is at least 80 percent."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Average"
  threshold           = 80
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[var.config.locations[each.value.location].aws.region].arn]
  ok_actions          = [aws_sns_topic.alerts[var.config.locations[each.value.location].aws.region].arn]

  dimensions = {
    InstanceId = each.value.id
  }

  tags = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "aws_cloudwatch_metric_alarm" "filesystem" {
  for_each = var.vms

  region              = var.config.locations[each.value.location].aws.region
  alarm_name          = "${each.value.name}-filesystem-high"
  alarm_description   = "Root filesystem utilization is at least 85 percent."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Average"
  threshold           = 85
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[var.config.locations[each.value.location].aws.region].arn]
  ok_actions          = [aws_sns_topic.alerts[var.config.locations[each.value.location].aws.region].arn]

  dimensions = {
    InstanceId = each.value.id
  }

  tags = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "aws_cloudwatch_dashboard" "health" {
  count = local.monitoring_enabled ? 1 : 0

  region         = var.config.locations[var.config.default_location].aws.region
  dashboard_name = "${var.config.name_prefix}-${var.config.environment}-health"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title  = "Instance health"
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          region = var.config.locations[var.config.default_location].aws.region
          yAxis = {
            left = { min = 0, max = 1 }
          }
          metrics = [
            for name, vm in var.vms : [
              "AWS/EC2",
              "StatusCheckFailed",
              "InstanceId",
              vm.id,
              { label = vm.name, region = var.config.locations[vm.location].aws.region },
            ]
          ]
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "cpu" {
  count = local.monitoring_enabled ? 1 : 0

  region         = var.config.locations[var.config.default_location].aws.region
  dashboard_name = "${var.config.name_prefix}-${var.config.environment}-cpu"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title  = "CPU utilization"
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          region = var.config.locations[var.config.default_location].aws.region
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              {
                color = "#d62728"
                label = "Alarm threshold (80%)"
                value = 80
              },
            ]
          }
          metrics = [
            for name, vm in var.vms : [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              vm.id,
              { label = vm.name, region = var.config.locations[vm.location].aws.region },
            ]
          ]
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "filesystem" {
  count = local.monitoring_enabled ? 1 : 0

  region         = var.config.locations[var.config.default_location].aws.region
  dashboard_name = "${var.config.name_prefix}-${var.config.environment}-filesystem"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title  = "Root filesystem utilization"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          region = var.config.locations[var.config.default_location].aws.region
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              {
                color = "#d62728"
                label = "Alarm threshold (85%)"
                value = 85
              },
            ]
          }
          metrics = [
            for name, vm in var.vms : [
              "CWAgent",
              "disk_used_percent",
              "InstanceId",
              vm.id,
              { label = vm.name, region = var.config.locations[vm.location].aws.region },
            ]
          ]
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "budget" {
  count = local.monitoring_enabled ? 1 : 0

  region         = var.config.locations[var.config.default_location].aws.region
  dashboard_name = "${var.config.name_prefix}-${var.config.environment}-budget"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = merge(
          {
            title  = "Estimated monthly AWS spend"
            view   = "timeSeries"
            stat   = "Maximum"
            period = 21600
            region = "us-east-1"
            yAxis = {
              left = { min = 0 }
            }
            metrics = [
              [
                "AWS/Billing",
                "EstimatedCharges",
                "Currency",
                "USD",
                { label = "Estimated spend (USD)" },
              ],
            ]
          },
          try(var.config.monitoring.monthly_budget, null) != null ? {
            annotations = {
              horizontal = [
                {
                  color = "#d62728"
                  label = "Monthly budget (${var.config.monitoring.monthly_budget.amount} ${var.config.monitoring.monthly_budget.currency})"
                  value = var.config.monitoring.monthly_budget.amount
                },
              ]
            }
          } : {},
        )
      },
    ]
  })
}

resource "aws_budgets_budget" "monthly" {
  count = local.monitoring_enabled && try(var.config.monitoring.monthly_budget, null) != null ? 1 : 0

  name         = "${var.config.name_prefix}-${var.config.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.config.monitoring.monthly_budget.amount)
  limit_unit   = var.config.monitoring.monthly_budget.currency
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.config.monitoring.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.config.monitoring.alert_email]
  }

  tags = merge(var.config.common_labels, { environment = var.config.environment })
}
