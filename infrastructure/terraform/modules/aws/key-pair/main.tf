locals {
  aws_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  locations = {
    for location in distinct([for vm in values(local.aws_vms) : vm.location]) :
    location => var.config.locations[location].aws
  }
  primary_location = var.config.vms.bastion.location
  location_suffixes = {
    for location in keys(local.locations) :
    location => location == local.primary_location ? "" : "-${location}"
  }
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
}

resource "aws_key_pair" "bootstrap" {
  for_each = local.locations

  region     = each.value.region
  key_name   = "${local.resource_prefix}-bootstrap${local.location_suffixes[each.key]}"
  public_key = trimspace(one(values(var.config.ssh_users)))
  tags       = merge(var.config.common_labels, { Name = "${local.resource_prefix}-bootstrap" })
}
