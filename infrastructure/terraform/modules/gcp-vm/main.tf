resource "google_service_account" "workload" {
  account_id   = local.name
  display_name = local.name
  description  = "Runtime identity for the ${local.name} workload VM"
}

resource "google_compute_address" "public" {
  count = local.vm.assign_public_ip ? 1 : 0

  name   = "${local.name}-ip"
  labels = local.labels
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
resource "google_compute_instance" "workload" {
  name                      = local.name
  machine_type              = local.machine_type
  allow_stopping_for_update = true

  tags   = local.network_tags
  labels = local.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = local.image
      type   = local.boot_disk_type
      labels = local.labels
    }
  }

  network_interface {
    subnetwork = local.subnetwork_id
    network_ip = local.vm.internal_ip

    dynamic "access_config" {
      for_each = local.vm.assign_public_ip ? [1] : []

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

  lifecycle {
    precondition {
      condition     = !local.vm.assign_public_ip || contains(["ui", "bastion"], local.vm.role)
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
