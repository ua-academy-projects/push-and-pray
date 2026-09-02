locals {
  vm = merge(var.vm_defaults, var.vm)

  name                = "${var.resource_prefix}-${var.vm_name}"
  subnet_id           = local.vm.role == "bastion" ? var.management_subnet_id : var.workload_subnet_id
  security_group_ids  = [var.security_group_ids_by_role[local.vm.role]]
  instance_type       = var.provider_mappings.instance_types[local.vm.size].aws.instance_type
  image_ssm_parameter = var.provider_mappings.images[local.vm.image].aws.ssm_parameter
  root_volume_type    = var.provider_mappings.disk_types[local.vm.disk_type].aws
  tags                = merge(var.common_tags, try(local.vm.labels, {}), { role = local.vm.role })
}
