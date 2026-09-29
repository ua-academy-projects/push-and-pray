resource "google_compute_address" "ingress" {
  count = local.enabled ? 1 : 0

  name         = "${local.resource_prefix}-k3s-ingress"
  address_type = "EXTERNAL"
  region       = local.placement.region
  network_tier = "PREMIUM"
  labels       = local.labels
}

resource "google_compute_instance_group" "agents" {
  count = local.enabled ? 1 : 0

  name      = "${local.resource_prefix}-k3s-agents"
  zone      = local.placement.zone
  instances = [for name in sort(keys(local.agents)) : var.instance_self_links[name]]

  lifecycle {
    precondition {
      condition     = length(local.agents) >= 2
      error_message = "The external K3s ingress requires at least two k3s-agent VMs."
    }

    precondition {
      condition = alltrue([
        for vm in values(local.agents) :
        lookup(vm, "location", var.config.default_location) == local.location
      ])
      error_message = "All GCP K3s agents must use the default location while ingress uses one regional load balancer."
    }
  }
}

resource "google_compute_region_health_check" "ingress" {
  count = local.enabled ? 1 : 0

  name               = "${local.resource_prefix}-k3s-ingress"
  region             = local.placement.region
  check_interval_sec = 10
  timeout_sec        = 5

  tcp_health_check {
    port = 80
  }
}

resource "google_compute_region_backend_service" "ingress" {
  count = local.enabled ? 1 : 0

  name                  = "${local.resource_prefix}-k3s-ingress"
  region                = local.placement.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.ingress[0].id]

  backend {
    group          = google_compute_instance_group.agents[0].self_link
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "ingress" {
  count = local.enabled ? 1 : 0

  name                  = "${local.resource_prefix}-k3s-ingress"
  region                = local.placement.region
  ip_address            = google_compute_address.ingress[0].address
  ip_protocol           = "TCP"
  ports                 = [for port in var.config.network.ui_public_ports : tostring(port)]
  load_balancing_scheme = "EXTERNAL"
  backend_service       = google_compute_region_backend_service.ingress[0].id
  network_tier          = "PREMIUM"
}
