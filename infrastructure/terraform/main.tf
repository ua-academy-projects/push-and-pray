module "gcp_network" {
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0
  source = "./modules/gcp/network"

  resource_prefix = local.resource_prefix
  network_config  = local.config.network
  vms             = local.config.vms

  depends_on = [module.gcp_project]
}

module "gcp_vm" {
  source   = "./modules/gcp/vm"
  for_each = local.gcp_vms

  resource_prefix   = local.resource_prefix
  vm_name           = each.key
  vm                = each.value
  vm_defaults       = local.config.vm_defaults
  provider_mappings = local.config.provider_mappings
  common_labels     = local.config.common_labels
  ssh_users         = local.config.ssh_users

  management_subnet_id = module.gcp_network[0].management_subnet_id
  workload_subnet_id   = module.gcp_network[0].workload_subnet_id
  network_tags_by_role = module.gcp_network[0].network_tags

  depends_on = [module.gcp_project]
}

module "aws_network" {
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0
  source = "./modules/aws/network"

  resource_prefix = local.resource_prefix
  network_config  = local.config.network
  location_config = local.default_location
  vms             = local.config.vms
  tags            = local.config.common_labels
}

module "aws_key_pair" {
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0
  source = "./modules/aws/key-pair"

  resource_prefix = local.resource_prefix
  ssh_users       = local.config.ssh_users
  tags            = local.config.common_labels
}

module "aws_vm" {
  source   = "./modules/aws/vm"
  for_each = local.aws_vms

  resource_prefix   = local.resource_prefix
  vm_name           = each.key
  vm                = each.value
  vm_defaults       = local.config.vm_defaults
  provider_mappings = local.config.provider_mappings
  common_tags       = local.config.common_labels
  key_name          = module.aws_key_pair[0].key_name

  management_subnet_id       = module.aws_network[0].management_subnet_id
  workload_subnet_id         = module.aws_network[0].workload_subnet_id
  security_group_ids_by_role = module.aws_network[0].security_group_ids
}
