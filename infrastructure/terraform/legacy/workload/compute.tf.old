resource "google_compute_instance" "vm" {
  for_each = local.vm_roles

  name                      = "${local.name_prefix}-${each.key}"
  machine_type              = var.machine_types[each.key]
  zone                      = var.zone
  allow_stopping_for_update = true
  can_ip_forward            = false
  tags                      = [local.vm_network_tags[each.key]]
  labels                    = merge(local.common_labels, { role = each.key })

  metadata = {
    user-data = local.rendered_cloud_init[each.key]
  }

  boot_disk {
    auto_delete = true
    device_name = "${local.name_prefix}-${each.key}-boot"

    initialize_params {
      image = "projects/${var.boot_image_project}/global/images/family/${var.boot_image_family}"
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    network_ip = google_compute_address.vm_internal[each.key].address

    dynamic "access_config" {
      for_each = each.key == "ui" ? [1] : []

      content {
        nat_ip       = google_compute_address.ui_external.address
        network_tier = "PREMIUM"
      }
    }
  }

  service_account {
    email  = google_service_account.vm[each.key].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }
}

resource "google_compute_disk" "infra_data" {
  name   = "${local.name_prefix}-infra-data"
  type   = var.infra_data_disk_type
  zone   = var.zone
  size   = var.infra_data_disk_size_gb
  labels = merge(local.common_labels, { role = "infra-data" })
}

resource "google_compute_attached_disk" "infra_data" {
  disk        = google_compute_disk.infra_data.id
  instance    = google_compute_instance.vm["infra"].id
  device_name = "${local.name_prefix}-data"
  mode        = "READ_WRITE"
}
