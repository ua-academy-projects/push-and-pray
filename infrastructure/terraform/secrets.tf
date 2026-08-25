locals {
  all_secret_ids = distinct(flatten([
    for name, workload in local.config.workloads : workload.secret_ids
  ]))

  workload_secret_pairs = flatten([
    for name, workload in local.config.workloads : [
      for secret_id in workload.secret_ids : { vm_name = name, secret_id = secret_id }
    ]
  ])
}

resource "google_secret_manager_secret" "this" {
  for_each  = toset(local.all_secret_ids)
  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = { for pair in local.workload_secret_pairs : "${pair.vm_name}-${pair.secret_id}" => pair }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.vm[each.value.vm_name].service_account_email}"
}
