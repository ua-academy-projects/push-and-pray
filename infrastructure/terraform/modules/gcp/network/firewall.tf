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

resource "google_compute_firewall" "k3s_api" {
  for_each = {
    for location, roles in local.roles_by_location : location => roles
    if contains(roles, "k3s_server")
  }

  name    = "${local.resource_prefix}-allow-k3s-api${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_tags = [for role in ["k3s_server", "k3s_agent"] : local.network_tags[each.key][role] if contains(each.value, role)]
  target_tags = [local.network_tags[each.key].k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

resource "google_compute_firewall" "k3s_etcd" {
  for_each = {
    for location, roles in local.roles_by_location : location => roles
    if contains(roles, "k3s_server")
  }

  name    = "${local.resource_prefix}-allow-k3s-etcd${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_tags = [local.network_tags[each.key].k3s_server]
  target_tags = [local.network_tags[each.key].k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["2379-2380"]
  }
}

resource "google_compute_firewall" "k3s_nodes" {
  for_each = {
    for location, roles in local.roles_by_location : location => roles
    if contains(roles, "k3s_server")
  }

  name    = "${local.resource_prefix}-allow-k3s-nodes${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_tags = [for role in ["k3s_server", "k3s_agent"] : local.network_tags[each.key][role] if contains(each.value, role)]
  target_tags = [for role in ["k3s_server", "k3s_agent"] : local.network_tags[each.key][role] if contains(each.value, role)]

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }
}

resource "google_compute_firewall" "database_postgresql" {
  for_each = {
    for location, roles in local.roles_by_location : location => roles
    if var.config.database_mode == "postgres_extensions" && contains(roles, "k3s_server")
  }

  name    = "${local.resource_prefix}-allow-database-postgresql${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_tags = [for role in ["k3s_server", "k3s_agent"] : local.network_tags[each.key][role] if contains(each.value, role)]
  target_tags = [local.network_tags[each.key].k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "ingress_web" {
  for_each = {
    for location, vms in local.vms_by_location : location => vms
    if length([for vm in values(vms) : vm if vm.role != "bastion" && try(vm.assign_public_ip, false)]) > 0
  }

  name    = "${local.resource_prefix}-allow-ingress-web${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id

  source_ranges = ["0.0.0.0/0"]
  target_tags = [for vm in values(each.value) : "${local.resource_prefix}-${vm.role}"
  if vm.role != "bastion" && try(vm.assign_public_ip, false)]

  allow {
    protocol = "tcp"
    ports    = [for port in(try(var.config.cloudflare.enabled, false) ? [80, 443] : var.config.network.ingress_public_ports) : tostring(port)]
  }
}
