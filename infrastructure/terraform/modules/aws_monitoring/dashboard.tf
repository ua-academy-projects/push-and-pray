resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.resource_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        for chart in [
          { title = "VM CPU", metric = "cpu_usage_active" },
          { title = "VM memory", metric = "mem_used_percent" },
          { title = "VM root disk", metric = "disk_used_percent" },
          ] : {
          type   = "metric"
          width  = 8
          height = 6
          properties = {
            title  = chart.title
            region = local.region
            view   = "timeSeries"
            period = 300
            metrics = [[{
              expression = "SEARCH('{${local.namespace},InstanceId} MetricName=\"${chart.metric}\"', 'Average', 300)"
              id         = replace(chart.metric, "_", "")
              region     = local.region
            }]]
            yAxis = { left = { min = 0, max = 100 } }
          }
        }
      ],
      [
        {
          type = "metric", width = 12, height = 6
          properties = {
            title = "RabbitMQ", region = local.region, view = "timeSeries", stat = "Average", period = 300
            metrics = [
              [local.namespace, "rabbitmq_connections", "job", "rabbitmq"],
              [".", "rabbitmq_consumers", ".", "."],
              [".", "rabbitmq_queue_messages_ready", ".", "."],
              [".", "rabbitmq_queue_messages_unacked", ".", "."],
            ]
          }
        },
        {
          type = "metric", width = 12, height = 6
          properties = {
            title = "Redis", region = local.region, view = "timeSeries", stat = "Average", period = 300
            metrics = [
              [local.namespace, "redis_up", "job", "redis"],
              [".", "redis_connected_clients", ".", "."],
              [".", "redis_memory_used_bytes", ".", "."],
            ]
          }
        },
        {
          type = "metric", width = 24, height = 6
          properties = {
            title = "RDS PostgreSQL", region = local.region, view = "timeSeries", stat = "Average", period = 300
            metrics = [
              ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.database_identifier, { yAxis = "left" }],
              [".", "FreeStorageSpace", ".", ".", { yAxis = "right" }],
            ]
            yAxis = {
              left  = { min = 0, max = 100, label = "CPU %" }
              right = { min = 0, label = "Free bytes" }
            }
          }
        },
      ],
      [
        for name, check in aws_route53_health_check.ui : {
          type = "metric", width = 24, height = 4
          properties = {
            title   = "UI availability"
            region  = "us-east-1"
            view    = "singleValue"
            stat    = "Minimum"
            period  = 60
            metrics = [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", check.id]]
            yAxis   = { left = { min = 0, max = 1 } }
          }
        }
      ],
    )
  })
}
