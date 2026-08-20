resource "google_service_account" "bastion" {
  project      = var.project_id
  account_id   = "${local.prefix}-bastion-sa"
  display_name = "${local.prefix} bastion host"
  description  = "Dedicated identity for the bastion. Deliberately has almost no permissions."
}

# Session logs are the audit trail for "who used the bastion, when".
resource "google_project_iam_member" "bastion_log_writer" {
  count = var.grant_bastion_logging_roles ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

resource "google_project_iam_member" "bastion_metric_writer" {
  count = var.grant_bastion_logging_roles ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# A reserved static IP so the address in the team's ~/.ssh/config and in the
# corporate firewall allow-list survives instance recreation.
resource "google_compute_address" "bastion" {
  project      = var.project_id
  name         = "${local.prefix}-bastion-ip"
  description  = "Static external IP of the bastion host."
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  labels       = local.labels
}

#trivy:ignore:AVD-GCP-0031
resource "google_compute_instance" "bastion" {
  project     = var.project_id
  name        = "${local.prefix}-bastion"
  description = "SSH jump host. Only sshd on port ${var.ssh_port} is exposed, only to approved source ranges."

  zone         = var.zone
  machine_type = var.bastion_machine_type
  tags         = local.instance_tags
  labels       = local.labels

  # Never route other hosts' traffic through the bastion.
  can_ip_forward = false

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = var.bastion_image
      size   = var.bastion_disk_size_gb
      type   = "pd-balanced"
      labels = local.labels
    }
  }

  network_interface {
    subnetwork = var.subnetwork_id

    # The single external IP in this module.
    access_config {
      nat_ip       = google_compute_address.bastion.address
      network_tier = "PREMIUM"
    }
  }

  metadata                = local.common_metadata
  metadata_startup_script = local.startup_script

  service_account {
    email = google_service_account.bastion.email
    # cloud-platform + narrow IAM roles is the current recommendation; legacy
    # per-scope restriction is not a security boundary.
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    preemptible         = var.bastion_preemptible
    automatic_restart   = !var.bastion_preemptible
    provisioning_model  = var.bastion_preemptible ? "SPOT" : "STANDARD"
    on_host_maintenance = var.bastion_preemptible ? "TERMINATE" : "MIGRATE"
  }

  allow_stopping_for_update = true
}
