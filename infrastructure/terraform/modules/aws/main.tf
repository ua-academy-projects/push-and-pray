module "network" {
  source = "./modules/network"
  count  = length(local.my_vms) > 0 ? 1 : 0

  resource_prefix = local.resource_prefix

  network_cidr        = local.profile.network_cidr
  public_subnet_cidr  = local.profile.subnets.management
  private_subnet_cidr = local.profile.subnets.workload
  availability_zone   = local.profile.zone
  enable_nat_gateway  = local.needs_nat_gateway

  ui_public_ports = [
    for port in var.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = var.config.service_ports.history_api
  postgresql_port  = var.config.service_ports.postgresql

  tags = local.common_tags
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name = "${local.resource_prefix}-${each.key}"

  subnet_id = each.value.assign_public_ip ? module.network[0].public_subnet_id : module.network[0].private_subnet_id

  role      = each.value.role
  ssh_users = var.config.ssh_users

  security_group_ids = [
    for scope in each.value.network_tags :
    module.network[0].security_group_ids[scope]
  ]

  instance_type  = local.profile.machine_sizes[each.value.size]
  ami            = local.profile.images[each.value.image]
  boot_disk_type = local.profile.disk_types[each.value.boot_disk.type]

  private_ip        = each.value.internal_ip
  boot_disk_size_gb = each.value.boot_disk.size_gb
  assign_public_ip  = each.value.assign_public_ip

  tags = merge(
    local.common_tags,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )
}
