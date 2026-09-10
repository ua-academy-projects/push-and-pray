resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${var.resource_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPU utilization"
          view    = "timeSeries"
          region  = data.aws_region.current.region
          stat    = "Average"
          period  = local.period_seconds
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [for instance_id in values(var.instance_ids) : ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 status checks"
          view    = "timeSeries"
          region  = data.aws_region.current.region
          stat    = "Maximum"
          period  = local.period_seconds
          yAxis   = { left = { min = 0, max = 1 } }
          metrics = [for instance_id in values(var.instance_ids) : ["AWS/EC2", "StatusCheckFailed", "InstanceId", instance_id]]
        }
      }
    ]
  })
}

data "aws_region" "current" {}
