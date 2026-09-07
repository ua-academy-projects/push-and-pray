resource "google_compute_address" "public" {
  for_each = {
    for name, vm in local.vms : name => vm
    if vm.assign_public_ip
  }

  name   = "${local.resource_prefix}-${each.key}-ip"
  labels = local.labels[each.key]
}

resource "google_compute_instance" "vms" {
  for_each = local.vms

  name                      = "${local.resource_prefix}-${each.key}"
  zone                      = var.config.zones[var.config.location].gcp
  machine_type              = var.config.sizes[each.value.machine_type].gcp
  allow_stopping_for_update = true

  tags   = each.value.network_tags
  labels = local.labels[each.key]

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = var.config.images[each.value.image].gcp.image
      size   = each.value.boot_disk.size_gb
      type   = var.config.disk_types[each.value.boot_disk.type].gcp
      labels = local.labels[each.key]
    }
  }

  network_interface {
    subnetwork = each.value.role == "bastion" ? var.subnets.management_subnet_id : var.subnets.vm_subnet_id
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[each.key].address
      }
    }
  }

  dynamic "service_account" {
    for_each = each.value.role == "bastion" ? [] : [var.service_account_emails[each.key]]

    content {
      email  = service_account.value
      scopes = ["cloud-platform"]
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only VMs with role ui or bastion may receive a public IP."
    }
  }

  metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys" = join("\n", [
      for username, public_key in var.config.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }
}
