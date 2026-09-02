resource "google_compute_firewall" "bastion_ssh" {
  for_each = local.bastion_vm == null ? {} : local.instances

  name    = "${local.resource_prefix}-allow-bastion-ssh"
  network = google_compute_network.main[each.key].id

  source_ranges = local.bastion_vm.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(local.bastion_vm.ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  for_each = (
    local.bastion_vm != null &&
    var.config.network.enable_bastion_ssh_bootstrap &&
    try(local.bastion_vm.ssh_port, 22) != 22
  ) ? local.instances : {}

  name    = "${local.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = google_compute_network.main[each.key].id

  source_ranges = local.bastion_vm.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  for_each = local.bastion_vm != null && length(local.workload_roles) > 0 ? local.instances : {}

  name    = "${local.resource_prefix}-allow-workload-ssh"
  network = google_compute_network.main[each.key].id

  source_tags = [local.network_tags.bastion]
  target_tags = [for role in local.workload_roles : local.network_tags[role]]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  for_each = contains(local.roles, "ui") ? local.instances : {}

  name    = "${local.resource_prefix}-allow-ui-web"
  network = google_compute_network.main[each.key].id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = [for port in var.config.network.ui_public_ports : tostring(port)]
  }
}
