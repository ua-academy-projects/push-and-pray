resource "google_service_account" "workload" {
  for_each     = local.workloads
  project      = local.config.project_id
  account_id   = "${local.name_prefix}-${each.key}"
  display_name = "OilScope ${local.config.environment} ${title(each.key)} VM"
  description  = "Minimal runtime identity for the OilScope ${each.key} workload VM"
}

resource "google_project_iam_member" "workload_automation" {
  for_each = { for name, vm in local.workloads : name => vm if vm.automation_role != "none" }
  project  = local.config.project_id
  role     = "roles/editor"
  member   = "serviceAccount:${google_service_account.workload[each.key].email}"
}

resource "google_secret_manager_secret_iam_member" "workload_secret_access" {
  for_each  = { for pair in local.vm_secret_pairs : "${pair.vm_name}-${pair.secret_id}" => pair }
  project   = local.config.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload[each.value.vm_name].email}"
}
