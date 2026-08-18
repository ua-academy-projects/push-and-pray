module "workload_vm" {
  for_each = local.workloads
  source   = "./modules/vm"

  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  name         = "${local.name_prefix}-${each.key}"
  machine_type = each.value.machine_type

  subnetwork_id         = each.value.subnetwork_id
  internal_ip           = each.value.internal_ip
  assign_external_ip    = each.value.assign_external_ip
  network_tags          = [each.value.network_tag]
  service_account_email = google_service_account.workload[each.key].email

  boot_image        = "projects/${var.boot_image_project}/global/images/family/${var.boot_image_family}"
  boot_disk_size_gb = var.boot_disk_size_gb
  boot_disk_type    = var.boot_disk_type

  labels = merge(local.common_labels, { role = each.key })

  # Application cloud-init and deployment metadata are intentionally deferred.
  metadata = {}
}
