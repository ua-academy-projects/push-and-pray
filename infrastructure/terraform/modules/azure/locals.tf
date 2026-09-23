locals {
  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "azure"
  }

  has_selected_vms   = length(local.selected_vms) > 0
  resource_prefix    = "${var.config.name_prefix}-${var.config.environment}"
  location           = var.config.regions[var.config.region]["azure"].region
  managed_db_enabled = try(var.config.managed_db.enabled, false)

  rabbitmq_password_secret_id = try([
    for vm in var.config.vms : vm.secret_mappings.RABBITMQ_PASSWORD
    if try(vm.secret_mappings.RABBITMQ_PASSWORD, null) != null
  ][0], null)

  redis_password_secret_id = try([
    for vm in var.config.vms : vm.secret_mappings.REDIS_PASSWORD
    if try(vm.secret_mappings.REDIS_PASSWORD, null) != null
  ][0], null)

  postgres_password_secret_id = try([
    for vm in var.config.vms : vm.secret_mappings.POSTGRES_PASSWORD
    if try(vm.secret_mappings.POSTGRES_PASSWORD, null) != null
  ][0], null)
}