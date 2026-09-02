locals {
  aws_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  instances       = length(local.aws_vms) > 0 ? { this = true } : {}
  location        = try(var.config.locations[one(distinct([for vm in values(local.aws_vms) : vm.location]))].aws, null)
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
}

resource "aws_key_pair" "bootstrap" {
  for_each = local.instances

  region     = local.location.region
  key_name   = "${local.resource_prefix}-bootstrap"
  public_key = trimspace(one(values(var.config.ssh_users)))
  tags       = merge(var.config.common_labels, { Name = "${local.resource_prefix}-bootstrap" })
}
