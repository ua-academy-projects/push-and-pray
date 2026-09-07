resource "google_service_account" "workload" {
  for_each = local.selected_vms

  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
  description  = "Runtime identity for the ${each.key} workload VM"
}
