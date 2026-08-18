locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_labels = merge(
    {
      application = "oil-price-tracker"
      environment = var.environment
      managed_by  = "terraform"
    },
    var.common_labels
  )

  workloads = {
    infra = {
      machine_type       = var.machine_types.infra
      internal_ip        = var.internal_addresses.infra
      network_tag        = module.network.network_tags.infra
      subnetwork_id      = module.network.workload_subnet.id
      assign_external_ip = false
    }
    history = {
      machine_type       = var.machine_types.history
      internal_ip        = var.internal_addresses.history
      network_tag        = module.network.network_tags.history
      subnetwork_id      = module.network.workload_subnet.id
      assign_external_ip = false
    }
    fetcher = {
      machine_type       = var.machine_types.fetcher
      internal_ip        = var.internal_addresses.fetcher
      network_tag        = module.network.network_tags.fetcher
      subnetwork_id      = module.network.workload_subnet.id
      assign_external_ip = false
    }
    ui = {
      machine_type       = var.machine_types.ui
      internal_ip        = var.internal_addresses.ui
      network_tag        = module.network.network_tags.ui
      subnetwork_id      = module.network.workload_subnet.id
      assign_external_ip = true
    }
  }
}
