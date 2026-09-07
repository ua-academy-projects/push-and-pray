resource "google_compute_firewall" "bastion_ssh" {
  name    = "${local.resource_prefix}-allow-bastion-ssh"
  network = var.network_id

  source_ranges = var.config.vms.bastion.allowed_cidrs
  target_tags   = [var.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.vms.bastion.ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  # A fresh bastion listens on 22 until Ansible installs the final sshd policy.
  # This rule must be explicitly enabled and removed immediately after bootstrap.
  count = var.enable_bastion_ssh_bootstrap && var.config.vms.bastion.ssh_port != 22 ? 1 : 0

  name    = "${local.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = var.network_id

  source_ranges = var.config.vms.bastion.allowed_cidrs
  target_tags   = [var.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  name    = "${local.resource_prefix}-allow-workload-ssh"
  network = var.network_id

  source_tags = [var.network_tags.bastion]
  target_tags = [
    var.network_tags.infra,
    var.network_tags.history,
    var.network_tags.fetcher,
    var.network_tags.ui,
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
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
