resource "google_compute_firewall" "bastion_ssh" {
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-bastion-ssh"
  network = google_compute_network.main[0].id

  source_ranges = var.config.vms.bastion.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.vms.bastion.ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  # A fresh bastion listens on 22 until Ansible installs the final sshd policy.
  # This rule must be explicitly enabled and removed immediately after bootstrap.
  count = local.enabled && local.enable_bastion_ssh_bootstrap && var.config.vms.bastion.ssh_port != 22 ? 1 : 0

  name    = "${local.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = google_compute_network.main[0].id

  source_ranges = var.config.vms.bastion.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-workload-ssh"
  network = google_compute_network.main[0].id

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
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-ui-web"
  network = google_compute_network.main[0].id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = local.ui_public_ports
  }
}

resource "google_compute_firewall" "history_api" {
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-history-api"
  network = google_compute_network.main[0].id

  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.history_api)]
  }
}

resource "google_compute_firewall" "postgresql" {
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-postgresql"
  network = google_compute_network.main[0].id

  source_tags = [
    local.network_tags.fetcher,
    local.network_tags.history,
  ]

  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.postgresql)]
  }
}

resource "google_compute_firewall" "rabbitmq" {
  count       = local.enabled ? 1 : 0
  name        = "${local.resource_prefix}-rabbitmq"
  network     = google_compute_network.main[0].id
  source_tags = [local.network_tags.fetcher, local.network_tags.history]
  target_tags = [local.network_tags.history]
  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.rabbitmq.port)]
  }
}
