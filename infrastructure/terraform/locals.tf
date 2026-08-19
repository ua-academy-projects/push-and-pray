locals {
  name_prefix = "${local.config.name_prefix}-${local.config.environment}"
  config      = jsondecode(file(var.project_config_path))
  common_labels = merge(
    {
      application = "oil-price-tracker"
      environment = local.config.environment
      managed_by  = "terraform"
    },
    local.config.common_labels
  )

  workloads = {
    for vm in local.config.vms : vm.name => merge(vm, {
      subnetwork_id = module.network.workload_subnet.id
    })
  }

  vm_secret_pairs = flatten([
    for vm_name, vm in local.workloads : [
      for secret_id in vm.secret_ids : {
        vm_name   = vm_name
        secret_id = secret_id
      }
    ]
  ])

}
