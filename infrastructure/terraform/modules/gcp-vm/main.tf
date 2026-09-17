resource "google_compute_address" "public" {
  for_each = {
    for name, vm in local.vms : name => vm if vm.assign_public_ip
  }

  name   = "${each.value.resource_name}-ip"
  region = each.value.region
  labels = each.value.labels
}

resource "terraform_data" "cloud_init" {
  for_each = local.vms

  input = each.value.cloud_init
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

  name                      = each.value.resource_name
  zone                      = each.value.zone
  machine_type              = each.value.machine_type
  allow_stopping_for_update = true
  tags                      = each.value.provider_tags
  labels                    = each.value.labels

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
    subnetwork = each.value.subnet_id
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

  dynamic "service_account" {
    for_each = each.value.service_account_email == null ? [] : [each.value.service_account_email]

    content {
      email  = service_account.value
      scopes = ["cloud-platform"]
    }
  }

  metadata = each.value.metadata

  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init[each.key].output]
  }
}
