locals {
  project_id       = var.config.cloud_settings.gcp.project_id
  resource_prefix  = "${var.config.name_prefix}-${var.config.environment}"
  application_host = var.config.k3s.application.hostname
  application_ns   = var.config.k3s.application.namespace
  cluster_filter   = "resource.label.cluster_name=\"${var.cluster.name}\" AND resource.label.location=\"${var.cluster.location}\""
  notification_channels = compact([
    try(var.config.monitoring.gcp.notification_channel_id, null),
  ])

  metric_alerts = {
    node_cpu = {
      display_name         = "${local.resource_prefix}-gke-high-node-cpu"
      condition_name       = "Node CPU above 85 percent for 10 minutes"
      severity             = "WARNING"
      resource_type        = "k8s_node"
      metric_type          = "kubernetes.io/node/cpu/allocatable_utilization"
      additional_filter    = null
      comparison           = "COMPARISON_GT"
      threshold            = 0.85
      duration             = "600s"
      alignment_period     = "300s"
      per_series_aligner   = "ALIGN_MEAN"
      cross_series_reducer = null
      group_by_fields      = []
      documentation        = "A GKE worker node has used more than 85% of its allocatable CPU for 10 minutes. Inspect node and pod CPU usage in the OilScope GKE dashboard."
    }
    node_memory = {
      display_name         = "${local.resource_prefix}-gke-high-node-memory"
      condition_name       = "Node memory above 85 percent for 10 minutes"
      severity             = "WARNING"
      resource_type        = "k8s_node"
      metric_type          = "kubernetes.io/node/memory/allocatable_utilization"
      additional_filter    = null
      comparison           = "COMPARISON_GT"
      threshold            = 0.85
      duration             = "600s"
      alignment_period     = "300s"
      per_series_aligner   = "ALIGN_MEAN"
      cross_series_reducer = "REDUCE_MAX"
      group_by_fields      = ["resource.label.node_name"]
      documentation        = "A GKE worker node has used more than 85% of its allocatable memory for 10 minutes. Inspect memory use and recent workload changes before pods are evicted."
    }
    persistent_volume = {
      display_name         = "${local.resource_prefix}-gke-high-pvc-usage"
      condition_name       = "Application persistent volume above 85 percent for 10 minutes"
      severity             = "WARNING"
      resource_type        = "k8s_pod"
      metric_type          = "kubernetes.io/pod/volume/utilization"
      additional_filter    = "resource.label.namespace_name=\"${local.application_ns}\""
      comparison           = "COMPARISON_GT"
      threshold            = 0.85
      duration             = "600s"
      alignment_period     = "300s"
      per_series_aligner   = "ALIGN_MEAN"
      cross_series_reducer = null
      group_by_fields      = []
      documentation        = "A persistent volume used by a pod in the ${local.application_ns} namespace has remained above 85% utilization for 10 minutes. Check the PVC and expand or clean it before it fills."
    }
  }
}
