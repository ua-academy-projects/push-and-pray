resource "google_service_account" "vm" {
  for_each = local.vm_roles

  account_id   = "${local.name_prefix}-${each.key}"
  display_name = "OilScope ${var.environment} ${title(each.key)} VM"
  description  = "Runtime identity for the OilScope ${var.environment} ${each.key} VM"
}
