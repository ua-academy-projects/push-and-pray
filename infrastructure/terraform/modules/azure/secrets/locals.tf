locals {
  azure_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "azure"
  }

  database_enabled = var.config.default_cloud == "azure" && var.config.managed_database
  enabled          = length(local.azure_vms) > 0 || local.database_enabled

  all_secret_ids = distinct(flatten([
    for vm in values(local.azure_vms) : values(vm.secret_mappings)
  ]))

  workload_secret_pairs = flatten([
    for name, vm in local.azure_vms : [
      for secret_id in distinct(values(vm.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  settings = try(var.config.clouds.azure.key_vault, null)

  vault_name = coalesce(
    try(local.settings.name, null),
    "${substr(local.resource_prefix, 0, 17)}-${substr(sha256("${try(var.config.clouds.azure.subscription_id, "")}/${try(var.config.clouds.azure.resource_group_name, "")}"), 0, 6)}",
  )
}
