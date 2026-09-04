resource "google_service_account" "workload" {
  for_each = local.vms

  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
  description  = "Runtime identity for the ${local.resource_prefix}-${each.key} workload VM"
}

resource "google_compute_address" "public" {
  for_each = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  name   = "${local.resource_prefix}-${each.key}-ip"
  region = var.config.locations[each.value.location].gcp.region
  labels = merge(var.config.common_labels, try(each.value.labels, {}), { role = each.value.role })
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
resource "google_compute_instance" "workload" {
  for_each = local.vms

  name                      = "${local.resource_prefix}-${each.key}"
  machine_type              = var.config.provider_mappings.instance_types[each.value.size].gcp.machine_type
  zone                      = var.config.locations[each.value.location].gcp.zone
  allow_stopping_for_update = true

  tags   = [var.network_tags_by_location[each.value.location][each.value.role]]
  labels = merge(var.config.common_labels, try(each.value.labels, {}), { role = each.value.role })

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = var.config.provider_mappings.images[each.value.image].gcp.image
      type   = var.config.provider_mappings.disk_types[each.value.disk_type].gcp
      labels = merge(var.config.common_labels, try(each.value.labels, {}), { role = each.value.role })
    }
  }

  network_interface {
    subnetwork = local.subnet_ids_by_location[each.value.location][each.value.role]
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
