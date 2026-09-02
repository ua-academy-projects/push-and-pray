locals {
  vm = merge(var.vm_defaults, var.vm)

  name           = "${var.resource_prefix}-${var.vm_name}"
  subnetwork_id  = local.vm.role == "bastion" ? var.management_subnet_id : var.workload_subnet_id
  network_tags   = [var.network_tags_by_role[local.vm.role]]
  machine_type   = var.provider_mappings.instance_types[local.vm.size].gcp.machine_type
  image          = var.provider_mappings.images[local.vm.image].gcp.image
  boot_disk_type = var.provider_mappings.disk_types[local.vm.disk_type].gcp
  labels         = merge(var.common_labels, try(local.vm.labels, {}), { role = local.vm.role })
}
