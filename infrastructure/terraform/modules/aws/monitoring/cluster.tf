locals {
  cluster_namespace = "${var.config.name_prefix}-${var.config.environment}/Cluster"

  cluster_signals = {
    NodesNotReady = {
      description = "A cluster node is not Ready. On k3s, etcd keeps quorum while one is down, but losing the entry node takes the website and the API endpoint with it. On EKS the node group replaces the node and the load balancer stops sending it traffic."
      periods     = 2
    }
    PodsNotReady = {
      description = "A pod in the application namespace is not Ready. Check the migration Job, image pulls and dependency readiness."
      periods     = 3
    }
    JobsFailed = {
      description = "A Job in the application namespace has failed. The registry credential refresh lives here - if it stops, every image pull fails once the token expires about 12 hours later."
      periods     = 1
    }
    CertificatesNotReady = {
      description = "A cert-manager Certificate is not Ready. Renewal is stuck; the served certificate expires on its own schedule regardless."
      periods     = 2
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cluster" {
  for_each = local.alarms_enabled ? local.cluster_signals : {}

  alarm_name        = "${var.config.name_prefix}-${var.config.environment}-${each.key}"
  alarm_description = each.value.description

  namespace   = local.cluster_namespace
  metric_name = each.key
  statistic   = "Maximum"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = each.value.periods
  datapoints_to_alarm = each.value.periods
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts[0].arn]
  ok_actions    = [aws_sns_topic.alerts[0].arn]
  tags          = local.common_labels
}
