locals {
  config    = var.config
  cloud_key = "aws"

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  has_vms = length(local.resolved_vms) > 0

  bastion_vm = local.config.vms.bastion

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud_key
    },
    local.config.common_labels,
  )

  effective_cloud_by_vm = {
    for name, vm in local.config.vms :
    name => lookup(vm, "cloud", local.config.default_cloud)
  }

  selected_raw_vms = {
    for name, vm in local.config.vms :
    name => vm
    if local.effective_cloud_by_vm[name] == local.cloud_key
  }

  resolved_vms = {
    for name, vm in local.selected_raw_vms :
    name => merge(vm, {
      effective_cloud = local.effective_cloud_by_vm[name]
      location        = local.config.regions[vm.region][local.cloud_key]
      instance_type   = local.config.sizes[vm.size][local.cloud_key]
      disk_type       = local.config.disk_types[vm.boot_disk.type][local.cloud_key]
      image_config    = local.config.images[vm.image][local.cloud_key]
    })
  }

  workload_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.role != "bastion"
  }

  # Secret mappings are cloud-neutral configuration. This AWS wrapper turns
  # their secret IDs into AWS Secret Manager containers and, below, ARNs.
  all_secret_ids = distinct(flatten([
    for vm in values(local.workload_vms) : values(vm.secret_mappings)
  ]))

  secret_ids_by_vm = {
    for name, vm in local.workload_vms :
    name => distinct(values(vm.secret_mappings))
  }

  # Keys are stable VM names from the JSON. The ARN values become known after
  # the Secret Manager resources are created, which is safe for IAM policies.
  secret_arns_by_vm = {
    for name, secret_ids in local.secret_ids_by_vm :
    name => [
      for secret_id in secret_ids :
      module.secrets.secret_arns[secret_id]
    ]
  }
}
