resource "google_compute_address" "public" {
  count = var.vm.assign_public_ip ? 1 : 0

  name   = "${var.name}-ip"
  labels = var.labels
}

resource "google_compute_instance" "workload" {
  name                      = var.name
  machine_type              = local.machine_type
  allow_stopping_for_update = true

  tags   = var.network_tags
  labels = var.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = local.image
      size   = var.vm.boot_disk.size_gb
      type   = local.boot_disk_type
      labels = var.labels
    }
  }

  network_interface {
    subnetwork = var.subnetwork_id
    network_ip = var.vm.internal_ip

    dynamic "access_config" {
      for_each = var.vm.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[0].address
      }
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    precondition {
      condition     = !var.vm.assign_public_ip || contains(["ui", "bastion"], var.vm.role)
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

