resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.resource_prefix}-allow-bastion-ssh"
  network = google_compute_network.main.id

  source_ranges = local.bastion_vm.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(local.bastion_vm.ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  # A fresh bastion listens on 22 until Ansible installs the final sshd policy.
  # This rule must be explicitly enabled and removed immediately after bootstrap.
  count = var.network_config.enable_bastion_ssh_bootstrap && local.bastion_vm.ssh_port != 22 ? 1 : 0

  name    = "${var.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = google_compute_network.main.id

  source_ranges = local.bastion_vm.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  name    = "${var.resource_prefix}-allow-workload-ssh"
  network = google_compute_network.main.id

  source_tags = [local.network_tags.bastion]
  target_tags = [
    local.network_tags.database,
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
  network = google_compute_network.main.id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = [for port in var.network_config.ui_public_ports : tostring(port)]
  }
}
