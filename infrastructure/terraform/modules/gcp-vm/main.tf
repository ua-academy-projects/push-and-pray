resource "google_compute_address" "public" {
  for_each = {
    for name, vm in local.vms : name => vm if vm.assign_public_ip
  }

  name   = "${local.context.resource_prefix}-${each.key}-ip"
  region = each.value.region
  labels = each.value.labels
}

resource "google_compute_disk" "data" {
  for_each = local.data_disks

  name             = each.value.name
  zone             = each.value.zone
  size             = each.value.size_gb
  type             = each.value.type
  provisioned_iops = each.value.iops
  labels           = each.value.labels
}

resource "google_compute_instance" "this" {
  for_each = local.vms

  name                      = "${local.context.resource_prefix}-${each.key}"
  zone                      = each.value.zone
  machine_type              = each.value.machine_type
  allow_stopping_for_update = true

  tags = [
    for tag in each.value.tags :
    "${local.context.resource_prefix}-${each.value.location}-${tag}"
  ]
  labels = each.value.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image            = "projects/${each.value.image.project}/global/images/family/${each.value.image.family}"
      size             = each.value.boot_disk.size_gb
      type             = each.value.boot_disk.type
      provisioned_iops = each.value.boot_disk.iops
      labels           = each.value.labels
    }
  }

  dynamic "attached_disk" {
    for_each = each.value.data_disks

    content {
      source      = google_compute_disk.data["${each.key}/${attached_disk.key}"].id
      device_name = attached_disk.key
    }
  }

  network_interface {
    subnetwork = contains(each.value.tags, "bastion") ? var.networks[each.value.location].management_subnet_id : var.networks[each.value.location].workload_subnet_id
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[each.key].address
      }
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = var.service_account_emails[each.key]
    scopes = ["cloud-platform"]
  }

  metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys" = join("\n", [
      for username, public_key in var.config.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }
}
