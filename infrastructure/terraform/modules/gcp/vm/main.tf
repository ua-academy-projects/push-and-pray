resource "google_service_account" "workload" {
  for_each = var.vms

  account_id   = local.vm_names[each.key]
  display_name = local.vm_names[each.key]
  description  = "Runtime identity for the ${local.vm_names[each.key]} workload VM"
}

resource "google_compute_address" "public" {
  for_each = {
    for name, vm in var.vms :
    name => vm
    if vm.assign_public_ip
  }

  name   = "${local.vm_names[each.key]}-ip"
  region = each.value.location.region
  labels = local.labels_by_vm[each.key]
}

resource "google_compute_instance" "workload" {
  for_each = var.vms

  name                      = local.vm_names[each.key]
  machine_type              = each.value.instance_type
  zone                      = each.value.location.zone
  allow_stopping_for_update = true

  tags   = local.network_tags_by_vm[each.key]
  labels = local.labels_by_vm[each.key]

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = each.value.image_config.reference
      size   = each.value.boot_disk.size_gb
      type   = each.value.disk_type
      labels = local.labels_by_vm[each.key]
    }
  }

  network_interface {
    subnetwork = local.subnet_ids_by_vm[each.key]
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[each.key].address
      }
    }
  }

  service_account {
    email  = google_service_account.workload[each.key].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }

  metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys" = join("\n", [
      for username, public_key in var.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }
}
