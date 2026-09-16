data "aws_partition" "current" {}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = var.role_names

  role       = each.value
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_log_group" "system" {
  for_each = local.regions

  region            = each.key
  name              = "/oilscope/system"
  retention_in_days = var.config.monitoring.aws.log_retention_days
}

resource "aws_cloudwatch_log_group" "docker" {
  for_each = local.regions

  region            = each.key
  name              = "/oilscope/docker"
  retention_in_days = var.config.monitoring.aws.log_retention_days
}

resource "aws_cloudwatch_log_metric_filter" "http_requests" {
  for_each = local.regions

  region         = each.key
  name           = "${local.resource_prefix}-http-requests"
  pattern        = "%RequestMethod%"
  log_group_name = aws_cloudwatch_log_group.docker[each.key].name

  metric_transformation {
    name          = "HttpRequests"
    namespace     = "OilScope/${var.config.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  for_each = local.regions

  region         = each.key
  name           = "${local.resource_prefix}-http-5xx"
  pattern        = "%DownstreamStatus[^0-9]*5[0-9]{2}[^0-9]%"
  log_group_name = aws_cloudwatch_log_group.docker[each.key].name

  metric_transformation {
    name          = "Http5xxResponses"
    namespace     = "OilScope/${var.config.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "vm" {
  for_each = local.metric_alarms

  region              = each.value.region
  alarm_name          = each.value.name
  alarm_description   = each.value.description
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = local.notification_actions[each.value.region]
  ok_actions          = local.notification_actions[each.value.region]

  dynamic "metric_query" {
    for_each = {
      for index, name in sort(keys(each.value.instance_ids)) :
      "m${index + 1}" => each.value.instance_ids[name]
    }

    content {
      id          = metric_query.key
      return_data = false

      metric {
        dimensions = merge(each.value.dimensions, {
          InstanceId = metric_query.value
        })
        metric_name = each.value.metric_name
        namespace   = each.value.namespace
        period      = 300
        stat        = each.value.statistic
      }
    }
  }

  metric_query {
    id          = "q1"
    expression  = "MAX(METRICS())"
    label       = each.value.description
    period      = 300
    return_data = true
  }
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  for_each = local.regions

  region              = each.key
  alarm_name          = "${local.resource_prefix}-http-5xx"
  alarm_description   = "Traefik returned one or more HTTP 5xx responses within five minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  metric_name         = "Http5xxResponses"
  namespace           = "OilScope/${var.config.environment}"
  period              = 300
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.notification_actions[each.key]
  ok_actions          = local.notification_actions[each.key]

  depends_on = [aws_cloudwatch_log_metric_filter.http_5xx]
}

resource "aws_route53_health_check" "https" {
  for_each = local.aws_ui

  fqdn              = each.value.public_endpoint.hostname
  port              = 443
  type              = "HTTPS_STR_MATCH"
  resource_path     = "/health"
  search_string     = "\"status\":\"ok\""
  request_interval  = 30
  failure_threshold = 3
  enable_sni        = true

  tags = {
    Name        = "${local.resource_prefix}-https-availability"
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "https" {
  for_each = aws_route53_health_check.https

  region              = "us-east-1"
  alarm_name          = "${local.resource_prefix}-https-unavailable"
  alarm_description   = "The public OilScope HTTPS health endpoint is unavailable."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  treat_missing_data  = "breaching"
  alarm_actions       = try(local.notification_actions["us-east-1"], [])
  ok_actions          = try(local.notification_actions["us-east-1"], [])

  dimensions = {
    HealthCheckId = each.value.id
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  count = length(local.aws_ui) == 0 ? 0 : 1

  region         = local.dashboard_region
  dashboard_name = "Oilscope"
  dashboard_body = jsonencode({
    start          = "-PT1H"
    periodOverride = "inherit"
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title = "EC2 - CPU utilization", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for name, instance_id in local.dashboard_instance_ids :
            ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id, { label = "${local.resource_prefix}-${name}", stat = "Average" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title = "EC2 - Memory utilization", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for name, instance_id in local.dashboard_instance_ids :
            ["OilScope", "mem_used_percent", "InstanceId", instance_id, { label = "${local.resource_prefix}-${name}", stat = "Average" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title = "EC2 - Root disk utilization", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for name, instance_id in local.dashboard_instance_ids :
            ["OilScope", "disk_used_percent", "InstanceId", instance_id, "path", "/", "fstype", "ext4", { label = "${local.resource_prefix}-${name}", stat = "Average" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "EC2 - Network in", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for name, instance_id in local.dashboard_instance_ids :
            ["AWS/EC2", "NetworkIn", "InstanceId", instance_id, { label = "${local.resource_prefix}-${name}", stat = "Sum" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "EC2 - Network out", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for name, instance_id in local.dashboard_instance_ids :
            ["AWS/EC2", "NetworkOut", "InstanceId", instance_id, { label = "${local.resource_prefix}-${name}", stat = "Sum" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title = "EBS - Read operations", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for volume in values(local.dashboard_volume_ids) :
            ["AWS/EBS", "VolumeReadOps", "VolumeId", volume.volume_id, { label = volume.label, stat = "Sum" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title = "EBS - Write operations", region = local.dashboard_region, view = "timeSeries", period = 300
          metrics = [
            for volume in values(local.dashboard_volume_ids) :
            ["AWS/EBS", "VolumeWriteOps", "VolumeId", volume.volume_id, { label = volume.label, stat = "Sum" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 8, height = 6
        properties = {
          title                = "Requests in the last hour", region = local.dashboard_region, view = "singleValue", period = 60, stat = "Sum"
          start                = "-PT1H"
          setPeriodToTimeRange = true
          metrics              = [["OilScope/${var.config.environment}", "HttpRequests"]]
        }
      },
      {
        type = "metric", x = 8, y = 18, width = 8, height = 6
        properties = {
          title     = "HTTP 5xx responses", region = local.dashboard_region, view = "singleValue", period = 300, stat = "Sum"
          metrics   = [["OilScope/${var.config.environment}", "Http5xxResponses"]]
          sparkline = true
        }
      },
      {
        type = "metric", x = 16, y = 18, width = 8, height = 6
        properties = {
          title     = "HTTPS availability", region = "us-east-1", view = "singleValue", period = 60, stat = "Minimum"
          metrics   = [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", values(aws_route53_health_check.https)[0].id]]
          sparkline = true
        }
      },
      {
        type = "alarm", x = 0, y = 24, width = 12, height = 7
        properties = {
          title = "Oilscope alarm status", alarms = local.dashboard_alarm_arns, sortBy = "stateUpdatedTimestamp"
        }
      },
      {
        type = "log", x = 12, y = 24, width = 12, height = 7
        properties = {
          title = "Recent HTTP errors", region = local.dashboard_region, view = "table"
          query = "SOURCE '/oilscope/docker' | fields @timestamp, @message | filter @message like /DownstreamStatus[^0-9]*5[0-9]{2}[^0-9]/ | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
