resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.resource_prefix}-allow-bastion-ssh"
  network = var.network_id

  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.bastion_ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  count = var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22 ? 1 : 0

  name    = "${var.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = var.network_id

  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  name    = "${var.resource_prefix}-allow-workload-ssh"
  network = var.network_id

  source_tags = [local.network_tags.bastion]
  target_tags = [
    local.network_tags.infra,
    local.network_tags.history,
    local.network_tags.fetcher,
    local.network_tags.ui,
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  name    = "${var.resource_prefix}-allow-ui-web"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = var.ui_public_ports
  }
}

resource "google_compute_firewall" "history_api" {
  name    = "${var.resource_prefix}-allow-history-api"
  network = var.network_id

  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.history_api_port)]
  }
}

resource "google_compute_firewall" "postgresql" {
  name    = "${var.resource_prefix}-allow-postgresql"
  network = var.network_id

  source_tags = [
    local.network_tags.fetcher,
    local.network_tags.history,
    local.network_tags.ui,
  ]
  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.postgresql_port)]
  }
}
