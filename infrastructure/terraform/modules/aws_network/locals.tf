locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  roles = toset([
    for vm in values(var.config.vms) : vm.role
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  ])

  bastion_ssh_rules = {
    for pair in setproduct(
      toset(var.config.vms.bastion.allowed_cidrs),
      toset([22, var.config.vms.bastion.ssh_port]),
    ) :
    "${pair[0]}/${pair[1]}" => {
      cidr = pair[0]
      port = pair[1]
    }
    if contains(local.roles, "bastion")
  }
}
