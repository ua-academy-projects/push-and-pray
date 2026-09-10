resource "google_compute_firewall" "bastion_ssh" {
  count = local.bastion != null ? 1 : 0

  name    = "${local.resource_prefix}-allow-bastion-ssh"
  network = var.network_id

  source_ranges = local.bastion.allowed_cidrs
  target_tags   = [var.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = local.bastion_ssh_ports
  }
}

resource "google_compute_firewall" "workload_ssh" {
  count = local.bastion != null && length(local.workload_target_tags) > 0 ? 1 : 0

  name    = "${local.resource_prefix}-allow-workload-ssh"
  network = var.network_id

  source_tags = [var.network_tags.bastion]
  target_tags = local.workload_target_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  count = local.tag_present["ui"] ? 1 : 0
  name    = "${local.resource_prefix}-allow-ui-web"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = local.ui_public_ports_str
  }
}

resource "google_compute_firewall" "history_api" {
  count = local.tag_present["history"] && local.tag_present["ui"] ? 1 : 0
  name    = "${local.resource_prefix}-allow-history-api"
  network = var.network_id

  source_tags = [var.network_tags.ui]
  target_tags = [var.network_tags.history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.history_api)]
  }
}

resource "google_compute_firewall" "postgresql" {
  count = local.tag_present["infra"] ? 1 : 0
  name    = "${local.resource_prefix}-allow-postgresql"
  network = var.network_id

  source_tags = [
    var.network_tags.fetcher,
    var.network_tags.history,
    var.network_tags.ui,
  ]

  target_tags = [var.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.postgresql)]
  }
}
