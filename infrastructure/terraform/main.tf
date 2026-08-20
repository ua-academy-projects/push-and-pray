module "network" {
  source = "./modules/network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  bastion_ssh_port      = local.config.bastion.ssh_port
  bastion_allowed_cidrs = local.config.bastion.allowed_cidrs

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql
}

module "bastion" {
  source = "./modules/bastion"

  resource_prefix = local.resource_prefix
  subnetwork_id   = module.network.management_subnet_id
  network_tag     = module.network.network_tags.bastion

  machine_type      = local.config.bastion.machine_type
  image             = local.config.bastion.image
  boot_disk_size_gb = local.config.bastion.boot_disk.size_gb
  boot_disk_type    = local.config.bastion.boot_disk.type

  labels = local.common_labels
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.config.workloads

  name          = "${local.resource_prefix}-${each.key}"
  subnetwork_id = module.network.workload_subnet_id
  network_tag   = module.network.network_tags[each.key]

  machine_type = each.value.machine_type
  image        = each.value.image
  internal_ip  = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk.type

  assign_public_ip = each.key == "ui"

  labels = merge(local.common_labels, {
    role = each.key
  })
}