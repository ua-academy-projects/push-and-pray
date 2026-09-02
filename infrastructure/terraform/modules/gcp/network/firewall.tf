resource "google_compute_firewall" "bastion_ssh" {
  for_each = {
    for location, vm in local.bastion_vms_by_location : location => vm if vm != null
  }

  name    = "${local.resource_prefix}-allow-bastion-ssh${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_ranges = each.value.allowed_cidrs
  target_tags   = [local.network_tags[each.key].bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(each.value.ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  for_each = {
    for location, vm in local.bastion_vms_by_location : location => vm
    if vm != null && var.config.network.enable_bastion_ssh_bootstrap && try(vm.ssh_port, 22) != 22
  }

  name    = "${local.resource_prefix}-allow-bastion-ssh-bootstrap${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_ranges = each.value.allowed_cidrs
  target_tags   = [local.network_tags[each.key].bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  for_each = {
    for location, roles in local.workload_roles_by_location : location => roles
    if local.bastion_vms_by_location[location] != null && length(roles) > 0
  }

  name    = "${local.resource_prefix}-allow-workload-ssh${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_tags = [local.network_tags[each.key].bastion]
  target_tags = [for role in each.value : local.network_tags[each.key][role]]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  for_each = {
    for location, roles in local.roles_by_location : location => roles if contains(roles, "ui")
  }

  name    = "${local.resource_prefix}-allow-ui-web${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags[each.key].ui]

  allow {
    protocol = "tcp"
    ports    = [for port in var.config.network.ui_public_ports : tostring(port)]
  }
}
