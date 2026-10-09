locals {
  resource_prefix  = "${var.config.name_prefix}-${var.config.environment}"
  cluster_name     = var.cluster.name
  region           = var.cluster.location
  application_ns   = var.config.k3s.application.namespace
  application_host = var.config.k3s.application.hostname
  notification_email = try(
    var.config.monitoring.aws.notification_email,
    null,
  )
  notification_regions = toset([local.region, "us-east-1"])
  managed_notification_regions = local.notification_email == null ? toset([]) : toset([
    for region in local.notification_regions : region
    if try(var.config.monitoring.aws.notification_topic_arns[region], null) == null
  ])
  notification_actions = {
    for region in local.notification_regions : region => compact([
      try(
        var.config.monitoring.aws.notification_topic_arns[region],
        aws_sns_topic.email[region].arn,
        null,
      ),
    ])
  }
  tags = merge(
    {
      Application = var.config.name_prefix
      Environment = var.config.environment
      ManagedBy   = "terraform"
    },
    { for key, value in var.config.common_labels : title(key) => value },
  )

  insights_alarms = {
    node_cpu = {
      name        = "${local.resource_prefix}-eks-high-node-cpu"
      description = "An EKS worker node has used more than 85 percent CPU for 10 minutes."
      query       = "SELECT MAX(node_cpu_utilization) FROM ContainerInsights WHERE ClusterName = '${local.cluster_name}'"
      threshold   = 85
    }
    node_memory = {
      name        = "${local.resource_prefix}-eks-high-node-memory"
      description = "An EKS worker node has used more than 85 percent memory for 10 minutes."
      query       = "SELECT MAX(node_memory_utilization) FROM ContainerInsights WHERE ClusterName = '${local.cluster_name}'"
      threshold   = 85
    }
    application_pod_cpu = {
      name        = "${local.resource_prefix}-eks-high-application-pod-cpu"
      description = "An OilScope application pod has used more than 90 percent CPU for 10 minutes."
      query       = "SELECT MAX(pod_cpu_utilization) FROM ContainerInsights WHERE ClusterName = '${local.cluster_name}' AND Namespace = '${local.application_ns}'"
      threshold   = 90
    }
    application_pod_memory = {
      name        = "${local.resource_prefix}-eks-high-application-pod-memory"
      description = "An OilScope application pod has used more than 90 percent memory for 10 minutes."
      query       = "SELECT MAX(pod_memory_utilization) FROM ContainerInsights WHERE ClusterName = '${local.cluster_name}' AND Namespace = '${local.application_ns}'"
      threshold   = 90
    }
  }
}
