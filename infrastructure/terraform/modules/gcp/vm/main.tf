resource "google_service_account" "workload" {
  for_each = local.selected_vms

  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
  description  = "Runtime identity for the ${each.key} workload VM"
}

resource "google_compute_address" "public" {
  for_each = { for name, vm in local.selected_vms : name => vm if vm.assign_public_ip }

  name   = "${local.resource_prefix}-${each.key}-ip"
  labels = merge(local.merged_common_labels, try(each.value.labels, {}), { role = each.value.role })
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
resource "google_compute_instance" "workload" {
  for_each = local.selected_vms

  name                      = "${local.resource_prefix}-${each.key}"
  machine_type              = var.machine_types[each.value.machine_type]["gcp"]
  allow_stopping_for_update = true

  tags = [
    for tag in each.value.network_tags :
    "${local.resource_prefix}-${tag}"
  ]
  labels = merge(local.merged_common_labels, try(each.value.labels, {}), { role = each.value.role })

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = var.images[coalesce(try(each.value.image, null), var.default_image)]["gcp"]
      size   = each.value.boot_disk.size_gb
      type   = var.disk_types[each.value.boot_disk.type]["gcp"]
      labels = merge(local.merged_common_labels, try(each.value.labels, {}), { role = each.value.role })
    }
  }

  network_interface {
    subnetwork = each.value.role == "bastion" ? var.management_subnet_id : var.workload_subnet_id
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
