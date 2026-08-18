resource "google_compute_address" "internal" {
  project      = var.project_id
  name         = "${var.name}-internal-ip"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = var.subnetwork_id
  address      = var.internal_ip
}

resource "google_compute_address" "external" {
  count = var.assign_external_ip ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-external-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  labels       = var.labels
}

resource "google_compute_instance" "this" {
  project                   = var.project_id
  name                      = var.name
  zone                      = var.zone
  machine_type              = var.machine_type
  allow_stopping_for_update = true
  can_ip_forward            = false
  tags                      = var.network_tags
  labels                    = var.labels
  metadata                  = var.metadata

  boot_disk {
    auto_delete = true
    device_name = "${var.name}-boot"

    initialize_params {
      image  = var.boot_image
      size   = var.boot_disk_size_gb
      type   = var.boot_disk_type
      labels = var.labels
    }
  }

  network_interface {
    subnetwork = var.subnetwork_id
    network_ip = google_compute_address.internal.address

    dynamic "access_config" {
      for_each = var.assign_external_ip ? [1] : []

      content {
        nat_ip       = google_compute_address.external[0].address
        network_tier = "PREMIUM"
      }
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
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
