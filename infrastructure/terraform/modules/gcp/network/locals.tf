locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  # GCP network tags allow only [a-z0-9-] — no underscores — so role names with
  # underscores (k3s_server) map to hyphenated tag values (k3s-server).
  network_tags = {
    bastion    = "${local.resource_prefix}-bastion"
    infra      = "${local.resource_prefix}-infra"
    history    = "${local.resource_prefix}-history"
    fetcher    = "${local.resource_prefix}-fetcher"
    ui         = "${local.resource_prefix}-ui"
    k3s_server = "${local.resource_prefix}-k3s-server"
    k3s_agent  = "${local.resource_prefix}-k3s-agent"
    gke_node   = "${local.resource_prefix}-gke-node"
  }

  gke_pods_range_name     = "${local.resource_prefix}-gke-pods"
  gke_services_range_name = "${local.resource_prefix}-gke-services"

  gke_secondary_ranges = var.managed_kubernetes_enabled ? [
    {
      range_name    = local.gke_pods_range_name
      ip_cidr_range = "10.64.0.0/16"
    },
    {
      range_name    = local.gke_services_range_name
      ip_cidr_range = "10.65.0.0/20"
    },
  ] : []
}
