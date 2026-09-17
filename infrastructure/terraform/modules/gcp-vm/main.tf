resource "google_compute_address" "public" {
  for_each = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  name   = "${local.resource_prefix}-${each.key}-ip"
  labels = merge(lookup(each.value, "labels", {}), local.common_tags, { role = each.value.role })
}

resource "google_compute_instance" "workload" {
  for_each                  = local.resolved_vms
  name                      = "${local.resource_prefix}-${each.key}"
  machine_type              = each.value.machine_type
  allow_stopping_for_update = true

  tags   = [for tag in each.value.network_tags : "${local.resource_prefix}-${tag}"]
  labels = merge(lookup(each.value, "labels", {}), local.common_tags, { role = each.value.role })

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = each.value.image
      size   = each.value.boot_disk.size_gb
      type   = each.value.boot_disk.type
      labels = merge(lookup(each.value, "labels", {}), local.common_tags, { role = each.value.role })
    }
  }

  network_interface {
    subnetwork = var.subnet_ids[each.value.role == "bastion" ? "management" : "workload"]
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[each.key].address
      }
    }
  }

  service_account {
    email  = var.service_account_emails[each.key]
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
    "enable-oslogin"            = "FALSE"
    "oilscope-database-mode"    = var.database_runtime.mode
    "oilscope-database-cloud"   = var.database_runtime.cloud
    "oilscope-database-host"    = var.database_runtime.host
    "oilscope-database-port"    = tostring(var.database_runtime.port)
    "oilscope-database-name"    = var.database_runtime.name
    "oilscope-database-user"    = var.database_runtime.username
    "oilscope-database-sslmode" = var.database_runtime.sslmode
    "oilscope-database-secret"  = var.database_runtime.secret_reference
    "oilscope-queue-backend"    = var.database_runtime.queue_backend
    "oilscope-queue-host"       = var.database_runtime.queue_host
    "oilscope-queue-port"       = tostring(var.database_runtime.queue_port)
    "oilscope-queue-username"   = var.database_runtime.queue_username
    "oilscope-queue-vhost"      = var.database_runtime.queue_vhost
    "oilscope-queue-secret"     = var.database_runtime.queue_secret_reference
    "ssh-keys" = join("\n", [
      for username, public_key in var.config.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }
}

resource "google_compute_disk" "additional" {
  for_each = local.disks
  name     = "${local.resource_prefix}-${each.key}"
  size     = each.value.size_gb
  type     = local.cloud_config.disk_types[each.value.type]
  labels   = local.common_tags
}
