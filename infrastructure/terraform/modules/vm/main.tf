resource "google_service_account" "workload" {
  for_each = local.resolved_vms

  account_id   = each.value.name
  display_name = each.value.name
  description  = "Runtime identity for the ${each.value.name} workload VM"
}

resource "google_compute_address" "public" {
  for_each = local.public_vms

  name   = "${each.value.name}-ip"
  labels = each.value.labels
}

resource "google_compute_instance" "workload" {
  for_each = local.resolved_vms

  name                      = each.value.name
  machine_type              = each.value.machine_type
  allow_stopping_for_update = true

  tags   = ["${var.resource_prefix}-${each.value.role == "database" ? "infra" : each.value.role}"]
  labels = each.value.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = format("projects/%s/global/images/family/%s", each.value.image_settings.project, each.value.image_settings.family)
      size   = each.value.boot_disk.size_gb
      type   = each.value.disk_type
      labels = each.value.labels
    }
  }

  network_interface {
    subnetwork = each.value.role == "bastion" ? var.network.management_subnet_id : var.network.workload_subnet_id

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
      condition     = each.value.boot_disk.size_gb >= 10
      error_message = "boot_disk_size_gb must be at least 10 GiB."
    }
    precondition {
      condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], each.value.disk_type)
      error_message = "boot_disk_type must be pd-standard, pd-balanced, or pd-ssd."
    }

    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", each.value.name))
      error_message = "VM names must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
    }
    precondition {
      condition     = startswith(each.value.provider_zone, "${each.value.provider_region}-")
      error_message = "Every provider zone must belong to its resolved provider region."
    }
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }

  metadata = merge({
    "enable-oslogin" = "FALSE"
    "ssh-keys" = join("\n", [
      for username, public_key in var.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
    }, lookup(var.startup_scripts, each.key, "") == "" ? {} : {
    "startup-script" = var.startup_scripts[each.key]
  })
}
