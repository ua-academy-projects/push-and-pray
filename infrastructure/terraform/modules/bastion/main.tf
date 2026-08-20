resource "google_service_account" "bastion" {
  account_id   = "${var.resource_prefix}-bastion"
  display_name = "${var.resource_prefix} bastion"
  description  = "Runtime identity for the bastion VM"
}

resource "google_compute_address" "bastion" {
  name   = "${var.resource_prefix}-bastion-ip"
  labels = var.labels
}

#trivy:ignore:AVD-GCP-0031
resource "google_compute_instance" "bastion" {
  name                      = "${var.resource_prefix}-bastion"
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

    access_config {
      nat_ip = google_compute_address.bastion.address
    }
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # TODO: Configure SSH access, install ssh_users, and switch sshd to the configured port.
  metadata = {}
}