locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  workload_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "azure"
  }

  bastion_vms = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "azure" ? {
    bastion = merge(var.config.bastion, {
      secret_mappings = {}
    })
  } : {}

  vms = merge(local.workload_vms, local.bastion_vms)

  identities_requiring_secrets = {
    for name, vm in local.vms : name => vm if length(try(vm.secret_mappings, {})) > 0
  }

  shared_resources = length(local.vms) > 0 ? { main = true } : {}

  subscription_suffix = substr(replace(try(var.config.cloud_settings.azure.subscription_id, ""), "-", ""), 0, 8)
  key_vault_name = lower(trim(
    substr("${var.config.name_prefix}-${var.config.environment}-${local.subscription_suffix}", 0, 24),
    "-",
  ))
}
