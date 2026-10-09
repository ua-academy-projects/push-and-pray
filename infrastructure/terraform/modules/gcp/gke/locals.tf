locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  enabled = var.enabled

  project_id = try(var.config.project_id, null)
  region     = var.config.regions[var.config.region].gcp.region
  zone       = var.config.regions[var.config.region].gcp.zone

  cluster_name = "${local.resource_prefix}-gke"

  master_ipv4_cidr_block = "172.16.0.0/28"

  node_count        = try(var.config.kubernetes.node_count, 3)
  node_machine_type = try(var.config.machine_types[var.config.kubernetes.node_machine_type].gcp, "e2-medium")

  node_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]

  merged_common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}
