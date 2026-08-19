module "workload_vm" {
  for_each = local.workloads
  source   = "./modules/vm"

  project_id   = local.config.project_id
  region       = local.config.region
  zone         = local.config.zone
  name         = "${local.name_prefix}-${each.key}"
  machine_type = each.value.machine_type

  subnetwork_id      = each.value.subnetwork_id
  internal_ip        = each.value.internal_ip
  assign_external_ip = each.value.assign_public_ip
  network_tags = distinct(concat(
    each.value.network_tags,
    [module.network.network_tags[each.value.role]],
  ))
  service_account_email = google_service_account.workload[each.key].email

  boot_image        = each.value.boot_image
  boot_disk_size_gb = each.value.boot_disk_size_gb
  boot_disk_type    = each.value.boot_disk_type

  labels = merge(local.common_labels, { role = each.value.role })

  # Application cloud-init and deployment metadata are intentionally deferred.
  metadata = {}
}
