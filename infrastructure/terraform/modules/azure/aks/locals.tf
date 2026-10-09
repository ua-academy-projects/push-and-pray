locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  enabled         = var.has_selected_vms && try(var.config.kubernetes.managed, false)
  cluster_name    = "${local.resource_prefix}-aks"

  bastion = try([
    for vm in var.selected_vms : vm
    if contains(vm.roles, "bastion")
  ][0], null)

  authorized_ip_ranges = distinct(concat(
    try(local.bastion.allowed_cidrs, []),
    var.bastion_public_ip == null ? [] : ["${var.bastion_public_ip}/32"],
  ))

  merged_common_tags = merge(
    {
      Application = var.config.name_prefix
      Environment = var.config.environment
      ManagedBy   = "terraform"
    },
    var.config.common_labels,
  )
}
