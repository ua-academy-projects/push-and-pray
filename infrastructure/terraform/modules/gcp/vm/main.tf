resource "google_service_account" "workload" {
  for_each = local.vms

  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
  description  = "Runtime identity for the ${local.resource_prefix}-${each.key} workload VM"
}

resource "google_project_iam_member" "monitoring_metric_writer" {
  for_each = local.vms

  project = var.config.clouds.gcp.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.workload[each.key].email}"
}

resource "google_project_iam_member" "logging_log_writer" {
  for_each = local.vms

  project = var.config.clouds.gcp.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workload[each.key].email}"
}

resource "google_compute_address" "public" {
  for_each = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  name   = "${local.resource_prefix}-${each.key}-ip"
  region = var.config.locations[each.value.location].gcp.region
  labels = local.labels_by_vm[each.key]
}

resource "google_compute_instance" "workload" {
  for_each = local.vms

  name                      = "${local.resource_prefix}-${each.key}"
  machine_type              = var.config.provider_mappings.instance_types[each.value.size].gcp.machine_type
  zone                      = var.config.locations[each.value.location].gcp.zone
  allow_stopping_for_update = true

  tags   = [var.network_tags_by_location[each.value.location][each.value.role]]
  labels = local.labels_by_vm[each.key]

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = var.config.provider_mappings.images[each.value.image].gcp.image
      size   = try(each.value.disk_size, null)
      type   = var.config.provider_mappings.disk_types[each.value.disk_type].gcp
      labels = local.labels_by_vm[each.key]
    }
  }

  dynamic "attached_disk" {
    for_each = each.value.disks

    content {
      source      = google_compute_disk.data["${each.key}-data-${attached_disk.key + 1}"].id
      device_name = "${each.key}-data-${attached_disk.key + 1}"
    }
  }

  network_interface {
    subnetwork = each.value.role == "bastion" ? var.management_subnet_ids[each.value.location] : var.workload_subnet_ids[each.value.location]
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

resource "google_compute_disk" "data" {
  for_each = local.data_disks

  name   = "${local.resource_prefix}-${each.key}"
  type   = var.config.provider_mappings.disk_types[each.value.disk_type].gcp
  zone   = var.config.locations[each.value.location].gcp.zone
  size   = each.value.disk_size
  labels = local.labels_by_vm[each.value.vm_name]
}
