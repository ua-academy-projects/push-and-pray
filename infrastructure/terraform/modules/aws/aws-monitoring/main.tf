resource "aws_sns_topic" "alerts" {
  count = length(var.instances) > 0 ? 1 : 0
  name  = "${var.name_prefix}-infrastructure-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = length(var.instances) > 0 && var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  for_each = var.instances

  alarm_name          = "${each.value.name}-status-check-failed"
  alarm_description   = "EC2 status check failed for ${each.value.name}"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = each.value.instance_id
  }

  alarm_actions = [aws_sns_topic.alerts[0].arn]
  ok_actions    = [aws_sns_topic.alerts[0].arn]
}

data "aws_region" "current" {}

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${var.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = flatten([
      for index, instance in values(var.instances) : [
        {
          type   = "metric"
          x      = 0
          y      = index * 6
          width  = 12
          height = 6

          properties = {
            title   = "${instance.name} CPU Utilization"
            view    = "timeSeries"
            stacked = false
            region  = data.aws_region.current.region
            period  = 300
            stat    = "Average"

            metrics = [
              [
                "AWS/EC2",
                "CPUUtilization",
                "InstanceId",
                instance.instance_id
              ]
            ]

            yAxis = {
              left = {
                min = 0
                max = 100
              }
            }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = index * 6
          width  = 12
          height = 6

          properties = {
            title   = "${instance.name} Status Check"
            view    = "timeSeries"
            stacked = false
            region  = data.aws_region.current.region
            period  = 60
            stat    = "Maximum"

            metrics = [
              [
                "AWS/EC2",
                "StatusCheckFailed",
                "InstanceId",
                instance.instance_id
              ]
            ]

            yAxis = {
              left = {
                min = 0
                max = 1
              }
            }
          }
        }
      ]
    ])
  })
}
