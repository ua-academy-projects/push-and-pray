resource "google_service_account" "workload" {
  for_each = local.workloads

  project      = var.project_id
  account_id   = "${local.name_prefix}-${each.key}"
  display_name = "OilScope ${var.environment} ${title(each.key)} VM"
  description  = "Minimal runtime identity for the OilScope ${each.key} workload VM"
}
