locals {
  workload_secret_access = {
    for name, vm in var.config.vms : name => distinct(values(vm.secret_mappings))
    if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
  }

  all_secret_ids = distinct(flatten(values(local.workload_secret_access)))

  workload_secret_pairs = flatten([
    for name, secret_ids in local.workload_secret_access : [
      for secret_id in secret_ids : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  secret_version_writers = {
    for pair in setproduct(sort(local.all_secret_ids), var.config.clouds.gcp.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}

resource "google_secret_manager_secret" "this" {
  for_each  = toset(local.all_secret_ids)
  secret_id = each.value
  labels    = var.config.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = {
    for pair in local.workload_secret_pairs :
    "${pair.vm_name}/${pair.secret_id}" => pair
  }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_emails[each.value.vm_name]}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
