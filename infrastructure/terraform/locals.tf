locals {
  config = jsondecode(file(var.project_config_path))

  bastion_vm = local.config.vms.bastion
  workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion"
  }

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
    },
    local.config.common_labels,
  )
}
