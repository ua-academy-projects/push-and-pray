module "network" {
  count  = length(local.gcp_vms) > 0 ? 1 : 0
  source = "./modules/network"

  resource_prefix = local.resource_prefix
  region          = local.gcp_region

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports :
    tostring(port)
  ]

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  enable_ui_direct_ssh = local.gcp_ui_direct_ssh

  depends_on = [google_project_service.required]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.gcp_vms

  name = "${local.resource_prefix}-${each.key}"

  subnetwork_id = (
    each.value.role == "bastion"
    ? module.network[0].management_subnet_id
    : module.network[0].workload_subnet_id
  )

  role                = each.value.role
  registry_repository = local.config.registry.repository
  image_sha           = local.config.registry.image_sha
  ssh_users           = local.config.ssh_users

  network_tags = [
    "${local.resource_prefix}-${each.value.role == "database" ? "infra" : each.value.role}"
  ]

  machine_type = each.value.machine_type

  image = format(
    "projects/%s/global/images/family/%s",
    each.value.image_settings.project,
    each.value.image_settings.family,
  )

  ssh_port = lookup(each.value, "ssh_port", 22)

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.disk_type

  assign_public_ip = each.value.assign_public_ip

  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      role        = each.value.role
      cloud       = each.value.cloud
    },
  )

  depends_on = [google_project_service.required]
}

module "aws_network" {
  count  = length(local.aws_vms) > 0 ? 1 : 0
  source = "./modules/aws_network"

  resource_prefix = local.resource_prefix

  vpc_cidr               = local.config.network.vpc_cidr
  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  availability_zone  = local.aws_zone
  enable_nat_gateway = local.config.network.aws_enable_nat_gateway

  enable_ui_direct_ssh = local.aws_ui_direct_ssh

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  ui_public_ports  = local.config.network.ui_public_ports
  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  tags = local.common_labels
}

module "aws_vm" {
  source   = "./modules/aws_vm"
  for_each = local.aws_vms

  name = "${local.resource_prefix}-${each.key}"
  role = each.value.role

  subnet_id = (
    each.value.role == "bastion" || each.value.role == "ui"
    ? module.aws_network[0].management_subnet_id
    : module.aws_network[0].workload_subnet_id
  )

  security_group_id = module.aws_network[0].security_group_ids[
    each.value.role
  ]

  instance_type = each.value.machine_type

  image_owners       = each.value.image_settings.owners
  image_name_pattern = each.value.image_settings.name_pattern

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.disk_type

  assign_public_ip = each.value.assign_public_ip

  ssh_users = local.config.ssh_users

  tags = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      Name        = "${local.resource_prefix}-${each.key}"
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      role        = each.value.role
      cloud       = each.value.cloud
    },
  )

  depends_on = [module.aws_network]
}
