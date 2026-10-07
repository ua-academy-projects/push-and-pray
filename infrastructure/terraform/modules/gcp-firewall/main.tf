resource "google_compute_firewall" "bastion_ssh" {
  for_each = local.bastions

  name    = "${local.resource_prefix}-${each.key}-allow-bastion-ssh"
  network = var.networks[each.key].network_id

  source_ranges = each.value.allowed_cidrs
  target_tags   = ["${local.resource_prefix}-${each.key}-bastion"]

  allow {
    protocol = "tcp"
    ports    = [tostring(each.value.ssh_port)]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  for_each = setintersection(local.workload_locations, toset(keys(local.bastions)))

  name    = "${local.resource_prefix}-${each.key}-allow-workload-ssh"
  network = var.networks[each.key].network_id

  source_tags = ["${local.resource_prefix}-${each.key}-bastion"]
  target_tags = [
    for tag in values(local.tags) : "${local.resource_prefix}-${each.key}-${tag.tag}"
    if tag.location == each.key && tag.tag != "bastion"
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "k3s_api" {
  for_each = local.k3s_server_locations

  name    = "${local.resource_prefix}-${each.key}-allow-k3s-api"
  network = var.networks[each.key].network_id

  source_tags = concat(
    contains(local.k3s_server_locations, each.key) ? ["${local.resource_prefix}-${each.key}-k3s-server"] : [],
    contains(local.k3s_agent_locations, each.key) ? ["${local.resource_prefix}-${each.key}-k3s-agent"] : [],
    contains(keys(local.bastions), each.key) ? ["${local.resource_prefix}-${each.key}-bastion"] : [],
  )
  target_tags = ["${local.resource_prefix}-${each.key}-k3s-server"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.k3s.api_server.port)]
  }
}

resource "google_compute_firewall" "k3s_api_health_checks" {
  for_each = local.k3s_server_locations

  name    = "${local.resource_prefix}-${each.key}-allow-k3s-api-health-checks"
  network = var.networks[each.key].network_id

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["${local.resource_prefix}-${each.key}-k3s-server"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.k3s.api_server.port)]
  }
}

resource "google_compute_firewall" "k3s_etcd" {
  for_each = local.k3s_server_locations

  name    = "${local.resource_prefix}-${each.key}-allow-k3s-etcd"
  network = var.networks[each.key].network_id

  source_tags = ["${local.resource_prefix}-${each.key}-k3s-server"]
  target_tags = ["${local.resource_prefix}-${each.key}-k3s-server"]

  allow {
    protocol = "tcp"
    ports    = ["2379", "2380"]
  }
}

resource "google_compute_firewall" "k3s_flannel_vxlan" {
  for_each = local.k3s_locations

  name    = "${local.resource_prefix}-${each.key}-allow-k3s-flannel-vxlan"
  network = var.networks[each.key].network_id

  source_tags = compact([
    contains(local.k3s_server_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-server" : null,
    contains(local.k3s_agent_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-agent" : null,
  ])
  target_tags = compact([
    contains(local.k3s_server_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-server" : null,
    contains(local.k3s_agent_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-agent" : null,
  ])

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }
}

resource "google_compute_firewall" "k3s_kubelet" {
  for_each = local.k3s_locations

  name    = "${local.resource_prefix}-${each.key}-allow-k3s-kubelet"
  network = var.networks[each.key].network_id

  source_tags = ["${local.resource_prefix}-${each.key}-k3s-server"]
  target_tags = compact([
    contains(local.k3s_server_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-server" : null,
    contains(local.k3s_agent_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-agent" : null,
  ])

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }
}

resource "google_compute_firewall" "k3s_ingress" {
  for_each = local.k3s_agent_locations

  name    = "${local.resource_prefix}-${each.key}-allow-k3s-ingress"
  network = var.networks[each.key].network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${local.resource_prefix}-${each.key}-k3s-agent"]

  allow {
    protocol = "tcp"
    ports    = [for port in var.config.network.ui_public_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "technitium_admin" {
  for_each = var.config.deployment_mode == "k3s" ? setintersection(
    local.k3s_locations,
    toset(keys(local.bastions)),
  ) : toset([])

  name    = "${local.resource_prefix}-${each.key}-allow-technitium-admin"
  network = var.networks[each.key].network_id

  source_tags = compact([
    contains(local.k3s_server_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-server" : null,
    contains(local.k3s_agent_locations, each.key) ? "${local.resource_prefix}-${each.key}-k3s-agent" : null,
  ])
  target_tags = ["${local.resource_prefix}-${each.key}-bastion"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.technitium_admin)]
  }
}

resource "google_compute_firewall" "ui_web" {
  for_each = toset([
    for tag in values(local.tags) : tag.location if tag.tag == "ui"
  ])

  name    = "${local.resource_prefix}-${each.key}-allow-ui-web"
  network = var.networks[each.key].network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${local.resource_prefix}-${each.key}-ui"]

  allow {
    protocol = "tcp"
    ports    = [for port in var.config.network.ui_public_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "history_api" {
  for_each = local.history_locations

  name    = "${local.resource_prefix}-${each.key}-allow-history-api"
  network = var.networks[each.key].network_id

  source_tags = ["${local.resource_prefix}-${each.key}-ui"]
  target_tags = ["${local.resource_prefix}-${each.key}-history"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.history_api)]
  }
}

resource "google_compute_firewall" "postgresql" {
  for_each = local.database_locations

  name    = "${local.resource_prefix}-${each.key}-allow-postgresql"
  network = var.networks[each.key].network_id

  source_tags = [
    for tag in ["fetcher", "history", "ui"] : "${local.resource_prefix}-${each.key}-${tag}"
    if contains(keys(local.tags), "${each.key}/${tag}")
  ]
  target_tags = ["${local.resource_prefix}-${each.key}-infrastructure"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.postgresql)]
  }
}

resource "google_compute_firewall" "rabbitmq" {
  count = var.config.database.mode == "managed" && var.config.default_cloud == "gcp" ? 1 : 0

  name    = "${local.resource_prefix}-${local.managed_database_location}-allow-rabbitmq"
  network = var.networks[local.managed_database_location].network_id

  source_tags = [
    "${local.resource_prefix}-${local.managed_database_location}-fetcher",
    "${local.resource_prefix}-${local.managed_database_location}-history",
  ]
  target_tags = ["${local.resource_prefix}-${local.managed_database_location}-infrastructure"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.rabbitmq)]
  }
}

resource "google_compute_firewall" "redis" {
  count = var.config.database.mode == "managed" && var.config.default_cloud == "gcp" ? 1 : 0

  name    = "${local.resource_prefix}-${local.managed_database_location}-allow-redis"
  network = var.networks[local.managed_database_location].network_id

  source_tags = ["${local.resource_prefix}-${local.managed_database_location}-ui"]
  target_tags = ["${local.resource_prefix}-${local.managed_database_location}-infrastructure"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.redis)]
  }
}
