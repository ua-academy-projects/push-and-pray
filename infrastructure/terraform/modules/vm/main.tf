resource "google_service_account" "workload" {
  account_id   = var.name
  display_name = var.name
  description  = "Runtime identity for the ${var.name} workload VM"
}

resource "google_compute_address" "public" {
  count = var.assign_public_ip ? 1 : 0

  name   = "${var.name}-ip"
  labels = var.labels
}

resource "google_compute_instance" "workload" {
  name                      = var.name
  machine_type              = var.machine_type
  allow_stopping_for_update = true

  tags   = [var.network_tag]
  labels = var.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = var.image
      size   = var.boot_disk_size_gb
      type   = var.boot_disk_type
      labels = var.labels
    }
  }

  network_interface {
    subnetwork = var.subnetwork_id
    network_ip = var.internal_ip

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[0].address
      }
    }
  }

  service_account {
    email  = google_service_account.workload.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  #TODO: Add workload cloud-init when guest provisioning
  metadata = {}
}