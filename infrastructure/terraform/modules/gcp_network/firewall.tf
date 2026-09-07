resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.config.name_prefix}-${var.config.environment}-allow-bastion-ssh"
  network = google_compute_network.main.id

  source_ranges = var.config.vms.bastion.allowed_cidrs
  target_tags   = var.config.vms.bastion.network_tags

  allow {
    protocol = "tcp"
    ports    = distinct(["22", tostring(var.config.vms.bastion.ssh_port)])
  }
}

resource "google_compute_firewall" "vms_ssh" {
  name    = "${var.config.name_prefix}-${var.config.environment}-allow-vms-ssh"
  network = google_compute_network.main.id

  source_tags = var.config.vms.bastion.network_tags
  target_tags = distinct(concat(
    var.config.vms.infra.network_tags,
    var.config.vms.history.network_tags,
    var.config.vms.fetcher.network_tags,
    var.config.vms.ui.network_tags,
  ))

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  name    = "${var.config.name_prefix}-${var.config.environment}-allow-ui-web"
  network = google_compute_network.main.id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.config.vms.ui.network_tags

  allow {
    protocol = "tcp"
    ports    = [for port in var.config.network.ui_public_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "history_api" {
  name    = "${var.config.name_prefix}-${var.config.environment}-allow-history-api"
  network = google_compute_network.main.id

  source_tags = var.config.vms.ui.network_tags
  target_tags = var.config.vms.history.network_tags

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.history_api)]
  }
}

resource "google_compute_firewall" "postgresql" {
  name    = "${var.config.name_prefix}-${var.config.environment}-allow-postgresql"
  network = google_compute_network.main.id

  source_tags = distinct(concat(
    var.config.vms.fetcher.network_tags,
    var.config.vms.history.network_tags,
    var.config.vms.ui.network_tags,
  ))

  target_tags = var.config.vms.infra.network_tags

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.postgresql)]
  }
}
