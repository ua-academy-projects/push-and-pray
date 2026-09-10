locals {
  monitoring_enabled = length(var.vms) > 0

  vm_regions = toset([
    for vm in values(var.vms) :
    var.config.locations[vm.location].aws.region
  ])
}
