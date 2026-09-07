resource "google_service_account" "workload" {
  for_each = local.gcp_vms

  account_id   = local.vm_names[each.key]
  display_name = local.vm_names[each.key]
  description  = "Runtime identity for the ${local.vm_names[each.key]} workload VM"
}

resource "google_compute_address" "public" {
  for_each = { for name, vm in local.gcp_vms : name => vm if vm.assign_public_ip }

  name   = "${local.vm_names[each.key]}-ip"
  labels = local.vm_labels[each.key]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
resource "google_compute_instance" "workload" {
  for_each = local.gcp_vms

  name                      = local.vm_names[each.key]
  machine_type              = each.value.native_vm_type
  allow_stopping_for_update = true

  tags   = local.vm_network_tags[each.key]
  labels = local.vm_labels[each.key]

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = each.value.native_image
      size   = each.value.disk_size_gb
      type   = each.value.native_disk_type
      labels = local.vm_labels[each.key]
    }
  }

  network_interface {
    subnetwork = local.subnetwork_ids[each.key]
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
      for username, public_key in var.config.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }
}
