resource "google_compute_address" "api" {
  count = local.enabled ? 1 : 0

  name         = "${local.resource_prefix}-k3s-api"
  address      = var.config.k3s.api_server.internal_ip
  address_type = "INTERNAL"
  region       = local.placement.region
  subnetwork   = var.networks[local.location].private_subnet_id
  labels       = local.labels
}

resource "google_compute_instance_group" "servers" {
  count = local.enabled ? 1 : 0

  name      = "${local.resource_prefix}-k3s-servers"
  zone      = local.placement.zone
  instances = [for name in sort(keys(local.servers)) : var.instance_self_links[name]]

  lifecycle {
    precondition {
      condition     = length(local.servers) >= 3 && length(local.servers) % 2 == 1
      error_message = "A K3s embedded-etcd control plane requires at least three and an odd number of k3s-server VMs."
    }

    precondition {
      condition     = length(local.agents) >= 2
      error_message = "The HA K3s topology requires at least two k3s-agent VMs."
    }

    precondition {
      condition = alltrue([
        for vm in values(local.nodes) :
        lookup(vm, "location", var.config.default_location) == local.location
      ])
      error_message = "All GCP K3s nodes must use the default location while the cluster uses one VPC and one zonal server instance group."
    }
  }
}

resource "google_compute_region_health_check" "api" {
  count = local.enabled ? 1 : 0

  name               = "${local.resource_prefix}-k3s-api"
  region             = local.placement.region
  check_interval_sec = 10
  timeout_sec        = 5

  tcp_health_check {
    port = var.config.k3s.api_server.port
  }
}

resource "google_compute_region_backend_service" "api" {
  count = local.enabled ? 1 : 0

  name                  = "${local.resource_prefix}-k3s-api"
  region                = local.placement.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.api[0].id]

  backend {
    group          = google_compute_instance_group.servers[0].self_link
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "api" {
  count = local.enabled ? 1 : 0

  name                  = "${local.resource_prefix}-k3s-api"
  region                = local.placement.region
  network               = var.networks[local.location].network_id
  subnetwork            = var.networks[local.location].private_subnet_id
  ip_address            = google_compute_address.api[0].address
  ip_protocol           = "TCP"
  ports                 = [tostring(var.config.k3s.api_server.port)]
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.api[0].id
}
