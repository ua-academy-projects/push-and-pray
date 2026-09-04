module "network" {
  count  = local.enabled ? 1 : 0
  source = "./modules/network"

  resource_prefix        = local.resource_prefix
  vpc_cidr               = var.config.network.vpc_cidr
  management_subnet_cidr = var.config.network.management_subnet_cidr
  workload_subnet_cidr   = var.config.network.workload_subnet_cidr
  availability_zone      = local.zone
  tags                   = local.common_tags

  bastion_ssh_port      = var.config.vms.bastion.ssh_port
  bastion_allowed_cidrs = var.config.vms.bastion.allowed_cidrs
  ui_public_ports       = var.config.network.ui_public_ports
  history_api_port      = var.config.service_ports.history_api
  postgresql_port       = var.config.service_ports.postgresql
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.vms

  name = "${local.resource_prefix}-${each.key}"
  role = each.value.role

  ami_id        = data.aws_ami.vm[each.key].id
  instance_type = each.value.machine_type

  subnet_id = lookup(
    local.subnet_id_by_class,
    lookup(local.subnet_class_by_role, each.value.role),
  )

  security_group_id = lookup(
    module.network[0].security_group_ids_by_role,
    each.value.role,
  )

  private_ip = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk.type

  assign_public_ip = each.value.assign_public_ip
  ssh_users        = var.config.ssh_users
  tags             = each.value.tags

  iam_instance_profile = aws_iam_instance_profile.vm[each.key].name

  depends_on = [module.network]
}