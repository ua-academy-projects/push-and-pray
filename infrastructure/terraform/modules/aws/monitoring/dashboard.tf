resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${var.resource_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = concat([
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
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "EC2 root disk usage"
          view    = "timeSeries"
          region  = data.aws_region.current.region
          stat    = "Average"
          period  = local.period_seconds
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [for instance_id in values(var.instance_ids) : ["CWAgent", "disk_used_percent", "InstanceId", instance_id]]
        }
      }
      ], var.managed_database_enabled ? [
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS PostgreSQL"
          view   = "timeSeries"
          region = data.aws_region.current.region
          stat   = "Average"
          period = local.period_seconds
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.database_instance_identifier],
            [".", "DatabaseConnections", ".", "."]
          ]
        }
      }
      ] : [], var.settings.logs.enabled ? [
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "Docker container logs"
          region = data.aws_region.current.region
          view   = "table"
          query  = "SOURCE '${local.log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      }
    ] : [])
  })
}

data "aws_region" "current" {}
