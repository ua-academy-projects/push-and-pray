locals {
  instance_metrics = {
    for name, instance in var.instances : name => instance.instance_id
  }
  volume_metrics = {
    for name, instance in var.instances : name => instance.root_volume_id
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.resource_prefix}-aws"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# OilScope AWS monitoring\nKickoff notifications are sent on ALARM; closure notifications are sent on OK."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "EC2 availability — status checks"
          view   = "timeSeries"
          region = var.region
          stat   = "Maximum"
          period = 60
          metrics = [
            for name, instance_id in local.instance_metrics :
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", instance_id, { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "CPU utilization"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "Warning 80%", value = 80, color = "#ff7f0e" }]
          }
          metrics = [
            for name, instance_id in local.instance_metrics :
            ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id, { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Memory used"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "Warning 80%", value = 80, color = "#ff7f0e" }]
          }
          metrics = [
            for name, instance_id in local.instance_metrics :
            ["CWAgent", "mem_used_percent", "InstanceId", instance_id, { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Root disk used"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "Warning 80%", value = 80, color = "#ff7f0e" }]
          }
          metrics = [
            for name, instance_id in local.instance_metrics :
            ["CWAgent", "disk_used_percent", "InstanceId", instance_id, "path", "/", "fstype", "ext4", { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "Application HTTP 5xx"
          view    = "timeSeries"
          region  = var.region
          stat    = "Sum"
          period  = 300
          metrics = [["OilScope/Application", "HTTP5xxCount", { label = "5xx count" }]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "Synthetic success"
          view    = "timeSeries"
          region  = var.region
          stat    = "Average"
          period  = 300
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [["CloudWatchSynthetics", "SuccessPercent", "CanaryName", aws_synthetics_canary.api.name]]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 20
        width  = 24
        height = 6
        properties = {
          title  = "Recent application errors"
          region = var.region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.application.name}' | fields @timestamp, @message | filter @message like /ERROR|HTTP\\/[0-9.]+\\\" 5[0-9][0-9]/ | sort @timestamp desc | limit 50"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 26
        width  = 12
        height = 6
        properties = {
          title  = "EC2 instance and system status checks"
          view   = "timeSeries"
          region = var.region
          stat   = "Maximum"
          period = 60
          metrics = concat(
            [for name, instance_id in local.instance_metrics :
              ["AWS/EC2", "StatusCheckFailed_Instance", "InstanceId", instance_id, { label = "${name} instance" }]
            ],
            [for name, instance_id in local.instance_metrics :
              ["AWS/EC2", "StatusCheckFailed_System", "InstanceId", instance_id, { label = "${name} system" }]
            ],
          )
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 26
        width  = 12
        height = 6
        properties = {
          title  = "Network traffic"
          view   = "timeSeries"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = concat(
            [for name, instance_id in local.instance_metrics :
              ["AWS/EC2", "NetworkIn", "InstanceId", instance_id, { label = "${name} in" }]
            ],
            [for name, instance_id in local.instance_metrics :
              ["AWS/EC2", "NetworkOut", "InstanceId", instance_id, { label = "${name} out" }]
            ],
          )
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 32
        width  = 12
        height = 6
        properties = {
          title  = "EBS root volume throughput"
          view   = "timeSeries"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = concat(
            [for name, volume_id in local.volume_metrics :
              ["AWS/EBS", "VolumeReadBytes", "VolumeId", volume_id, { label = "${name} read" }]
            ],
            [for name, volume_id in local.volume_metrics :
              ["AWS/EBS", "VolumeWriteBytes", "VolumeId", volume_id, { label = "${name} write" }]
            ],
          )
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 32
        width  = 12
        height = 6
        properties = {
          title  = "EBS queue length"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [for name, volume_id in local.volume_metrics :
            ["AWS/EBS", "VolumeQueueLength", "VolumeId", volume_id, { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 38
        width  = 12
        height = 6
        properties = {
          title  = "T-series CPU credit balance"
          view   = "timeSeries"
          region = var.region
          stat   = "Minimum"
          period = 300
          metrics = [for name, instance_id in local.instance_metrics :
            ["AWS/EC2", "CPUCreditBalance", "InstanceId", instance_id, { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 38
        width  = 12
        height = 6
        properties = {
          title  = "Synthetic failures and duration"
          view   = "timeSeries"
          region = var.region
          period = 300
          metrics = [
            ["CloudWatchSynthetics", "Failed", "CanaryName", aws_synthetics_canary.api.name, { label = "failed", stat = "Sum", yAxis = "left" }],
            ["CloudWatchSynthetics", "Duration", "CanaryName", aws_synthetics_canary.api.name, { label = "duration ms", stat = "Average", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 49
        width  = 24
        height = 6
        properties = {
          title  = var.database_identifier == null ? "RDS monitoring disabled" : "RDS CPU, connections, and free storage"
          view   = "timeSeries"
          region = var.region
          period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", coalesce(var.database_identifier, "not-enabled"), { label = "CPU %", stat = "Average" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", coalesce(var.database_identifier, "not-enabled"), { label = "connections", stat = "Average" }],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", coalesce(var.database_identifier, "not-enabled"), { label = "free bytes", stat = "Minimum", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 44
        width  = 24
        height = 5
        properties = {
          title  = "CloudWatch Logs ingestion"
          view   = "timeSeries"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Logs", "IncomingLogEvents", "LogGroupName", aws_cloudwatch_log_group.application.name, { label = "events" }],
            ["AWS/Logs", "IncomingBytes", "LogGroupName", aws_cloudwatch_log_group.application.name, { label = "bytes", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}
