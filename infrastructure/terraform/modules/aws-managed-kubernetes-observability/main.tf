data "aws_partition" "current" {}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${local.resource_prefix}-eks-cloudwatch-agent"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  region          = local.region
  cluster_name    = local.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = aws_iam_role.cloudwatch_agent.arn

  depends_on = [aws_iam_role_policy_attachment.cloudwatch_agent]
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset([
    "/aws/containerinsights/${local.cluster_name}/application",
    "/aws/containerinsights/${local.cluster_name}/dataplane",
    "/aws/containerinsights/${local.cluster_name}/host",
    "/aws/containerinsights/${local.cluster_name}/performance",
  ])

  region            = local.region
  name              = each.value
  retention_in_days = var.config.monitoring.aws.log_retention_days
  tags              = local.tags
}

resource "aws_eks_addon" "cloudwatch_observability" {
  region                      = local.region
  cluster_name                = local.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_cloudwatch_log_group.container_insights,
    aws_eks_pod_identity_association.cloudwatch_agent,
  ]
}

resource "aws_sns_topic" "email" {
  for_each = local.managed_notification_regions

  region = each.key
  name   = "${local.resource_prefix}-eks-alerts"
  tags   = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = local.managed_notification_regions

  region    = each.key
  topic_arn = aws_sns_topic.email[each.key].arn
  protocol  = "email"
  endpoint  = local.notification_email
}

resource "aws_cloudwatch_metric_alarm" "insights" {
  for_each = local.insights_alarms

  region              = local.region
  alarm_name          = each.value.name
  alarm_description   = each.value.description
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.threshold
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.notification_actions[local.region]
  ok_actions          = local.notification_actions[local.region]

  metric_query {
    id          = "q1"
    expression  = each.value.query
    label       = each.value.description
    period      = 300
    return_data = true
  }

  depends_on = [aws_eks_addon.cloudwatch_observability]
}

resource "aws_cloudwatch_metric_alarm" "failed_nodes" {
  region              = local.region
  alarm_name          = "${local.resource_prefix}-eks-failed-nodes"
  alarm_description   = "One or more EKS worker nodes have been unhealthy for five minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  metric_name         = "cluster_failed_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Maximum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.notification_actions[local.region]
  ok_actions          = local.notification_actions[local.region]

  dimensions = {
    ClusterName = local.cluster_name
  }

  depends_on = [aws_eks_addon.cloudwatch_observability]
}

resource "aws_route53_health_check" "https" {
  fqdn              = local.application_host
  port              = 443
  type              = "HTTPS_STR_MATCH"
  resource_path     = "/health"
  search_string     = "\"status\":\"ok\""
  request_interval  = 30
  failure_threshold = 3
  enable_sni        = true

  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-eks-https-availability"
  })
}

resource "aws_cloudwatch_metric_alarm" "https" {
  region              = "us-east-1"
  alarm_name          = "${local.resource_prefix}-eks-https-unavailable"
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
  alarm_actions       = local.notification_actions["us-east-1"]
  ok_actions          = local.notification_actions["us-east-1"]

  dimensions = {
    HealthCheckId = aws_route53_health_check.https.id
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  region         = local.region
  dashboard_name = "OilScope-EKS"
  dashboard_body = jsonencode({
    start          = "-PT1H"
    periodOverride = "inherit"
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "Nodes - CPU utilization", region = local.region, view = "timeSeries", period = 60
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,NodeName,InstanceId} MetricName=\"node_cpu_utilization\" ClusterName=\"${local.cluster_name}\"', 'Average', 60)"
            id         = "node_cpu"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Nodes - Memory utilization", region = local.region, view = "timeSeries", period = 60
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,NodeName,InstanceId} MetricName=\"node_memory_utilization\" ClusterName=\"${local.cluster_name}\"', 'Average', 60)"
            id         = "node_memory"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "Nodes - Filesystem utilization", region = local.region, view = "timeSeries", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,NodeName,InstanceId} MetricName=\"node_filesystem_utilization\" ClusterName=\"${local.cluster_name}\"', 'Average', 300)"
            id         = "node_filesystem"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "Pods - Count by namespace", region = local.region, view = "timeSeries", period = 60
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,Namespace} MetricName=\"namespace_number_of_running_pods\" ClusterName=\"${local.cluster_name}\"', 'Average', 60)"
            id         = "namespace_pods"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title = "OilScope pods - CPU utilization", region = local.region, view = "timeSeries", period = 60
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_cpu_utilization\" ClusterName=\"${local.cluster_name}\" Namespace=\"${local.application_ns}\"', 'Average', 60)"
            id         = "pod_cpu"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title = "OilScope pods - Memory utilization", region = local.region, view = "timeSeries", period = 60
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_memory_utilization\" ClusterName=\"${local.cluster_name}\" Namespace=\"${local.application_ns}\"', 'Average', 60)"
            id         = "pod_memory"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6
        properties = {
          title = "OilScope pods - Container restarts", region = local.region, view = "timeSeries", period = 300
          metrics = [[{
            expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_number_of_container_restarts\" ClusterName=\"${local.cluster_name}\" Namespace=\"${local.application_ns}\"', 'Maximum', 300)"
            id         = "pod_restarts"
            label      = ""
            region     = local.region
          }]]
        }
      },
      {
        type = "metric", x = 12, y = 18, width = 12, height = 6
        properties = {
          title = "OilScope pods - Network traffic", region = local.region, view = "timeSeries", period = 60
          metrics = [
            [{
              expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_network_rx_bytes\" ClusterName=\"${local.cluster_name}\" Namespace=\"${local.application_ns}\"', 'Average', 60)"
              id         = "network_rx"
              label      = "Received"
              region     = local.region
            }],
            [{
              expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_network_tx_bytes\" ClusterName=\"${local.cluster_name}\" Namespace=\"${local.application_ns}\"', 'Average', 60)"
              id         = "network_tx"
              label      = "Sent"
              region     = local.region
            }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 24, width = 8, height = 6
        properties = {
          title     = "HTTPS availability", region = "us-east-1", view = "singleValue", period = 60, stat = "Minimum"
          metrics   = [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.https.id]]
          sparkline = true
        }
      },
      {
        type = "alarm", x = 8, y = 24, width = 16, height = 6
        properties = {
          title = "EKS alarm status"
          alarms = concat(
            [for alarm in values(aws_cloudwatch_metric_alarm.insights) : alarm.arn],
            [aws_cloudwatch_metric_alarm.failed_nodes.arn],
            [aws_cloudwatch_metric_alarm.https.arn],
          )
          sortBy = "stateUpdatedTimestamp"
        }
      },
    ]
  })

  depends_on = [aws_eks_addon.cloudwatch_observability]
}
