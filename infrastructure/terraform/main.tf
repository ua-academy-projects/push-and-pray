module "gcp_network" {
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0
  source = "./modules/gcp-network"

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  depends_on = [module.gcp_project]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "gcp_vm" {
  source   = "./modules/gcp-vm"
  for_each = local.gcp_vms

  name                = "${local.resource_prefix}-${each.key}"
  subnetwork_id       = each.value.role == "bastion" ? module.gcp_network[0].management_subnet_id : module.gcp_network[0].workload_subnet_id
  role                = each.value.role
  registry_repository = local.config.registry.repository
  image_sha           = local.config.registry.image_sha
  ssh_users           = local.config.ssh_users
  network_tags        = [module.gcp_network[0].network_tags[each.value.role]]

  machine_type = each.value.instance_type_config.machine_type
  image        = each.value.provider_image.image
  internal_ip  = each.value.internal_ip
  ssh_port     = lookup(each.value, "ssh_port", 22)

  boot_disk_size_gb = each.value.size_config.boot_disk_size_gb
  boot_disk_type    = each.value.provider_disk_type
  assign_public_ip  = each.value.assign_public_ip

  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )

  depends_on = [module.gcp_project]
}

module "aws_network" {
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0
  source = "./modules/aws-network"

  resource_prefix        = local.resource_prefix
  vpc_cidr               = local.config.network.vpc_cidr
  availability_zone      = local.default_provider_locations.aws.availability_zone
  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr
  ui_public_ports        = local.config.network.ui_public_ports

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  history_api_port             = local.config.service_ports.history_api
  postgresql_port              = local.config.service_ports.postgresql

  tags = local.common_tags
}

resource "aws_key_pair" "bootstrap" {
  count = contains(local.enabled_clouds, "aws") ? 1 : 0

  key_name   = "${local.resource_prefix}-bootstrap"
  public_key = trimspace(one(values(local.config.ssh_users)))

  tags = merge(local.common_tags, { Name = "${local.resource_prefix}-bootstrap" })
}

#trivy:ignore:AVD-AWS-0028[associate_public_ip_address=true]
module "aws_vm" {
  source   = "./modules/aws-vm"
  for_each = local.aws_vms

  name                = "${local.resource_prefix}-${each.key}"
  subnet_id           = each.value.role == "bastion" ? module.aws_network[0].management_subnet_id : module.aws_network[0].workload_subnet_id
  security_group_ids  = [module.aws_network[0].security_group_ids[each.value.role]]
  role                = each.value.role
  instance_type       = each.value.instance_type_config.instance_type
  image_ssm_parameter = each.value.provider_image.ssm_parameter
  internal_ip         = each.value.internal_ip
  key_name            = aws_key_pair.bootstrap[0].key_name

  root_volume_size_gb = each.value.size_config.boot_disk_size_gb
  root_volume_type    = each.value.provider_disk_type
  assign_public_ip    = each.value.assign_public_ip

  tags = merge(
    local.common_tags,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )
}
