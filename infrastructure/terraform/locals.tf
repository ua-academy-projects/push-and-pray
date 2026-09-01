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
  effective_cloud_by_vm = {
    for name, vm in local.config.vms :
    name => try(vm.cloud, local.config.default_cloud)
  }
  resolved_vms = {
    for name, vm in local.config.vms :
    name => merge(vm, {
      effective_cloud = local.effective_cloud_by_vm[name]
      location        = local.config.regions[vm.region][local.effective_cloud_by_vm[name]]
      instance_type   = local.config.sizes[vm.size][local.effective_cloud_by_vm[name]]
      disk_type       = local.config.disk_types[vm.boot_disk.type][local.effective_cloud_by_vm[name]]
    })
  }
  gcp_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.effective_cloud == "gcp"
  }

  aws_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.effective_cloud == "aws"
  }

  gcp_workload_vms = {
    for name, vm in local.gcp_vms :
    name => vm
    if vm.role != "bastion"
  }

  aws_workload_vms = {
    for name, vm in local.aws_vms :
    name => vm
    if vm.role != "bastion"
  }
}
