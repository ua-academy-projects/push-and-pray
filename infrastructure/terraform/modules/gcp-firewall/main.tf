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
  target_tags = ["${local.resource_prefix}-${each.key}-database"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.postgresql)]
  }
}
