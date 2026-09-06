module "gcp_network" {
  source = "./modules/gcp/network"
  count  = length(local.gcp_vms) > 0 ? 1 : 0

  resource_prefix = local.resource_prefix

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port      = local.bastion_vm.ssh_port
  bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs
  //enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  depends_on = [google_project_service.required]
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "gcp_vm" {
  source   = "./modules/gcp/vm"
  for_each = local.gcp_vms

  name                = "${local.resource_prefix}-${each.key}"
  subnetwork_id       = each.value.role == "bastion" ? module.gcp_network[0].management_subnet_id : module.gcp_network[0].workload_subnet_id
  role                = each.value.role
  registry_repository = local.config.registry.repository
  image_sha           = local.config.registry.image_sha
  ssh_users           = local.config.ssh_users
  network_tags = [
    for tag in each.value.network_tags :
    "${local.resource_prefix}-${tag}"
  ]

  machine_type = each.value.native_vm_type
  image        = each.value.native_image
  internal_ip  = each.value.internal_ip
  ssh_port     = lookup(each.value, "ssh_port", 22)

  boot_disk_size_gb = each.value.disk_size_gb
  boot_disk_type    = each.value.native_disk_type

  assign_public_ip = each.value.assign_public_ip


  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )

  depends_on = [google_project_service.required]
}

module "aws_network" {
  source = "./modules/aws/network"
  count  = length(local.aws_vms) > 0 ? 1 : 0

  resource_prefix        = local.resource_prefix
  vpc_cidr               = local.config.clouds.aws.vpc_cidr
  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr
  availability_zone      = local.config.region_map[local.config.region]["aws"].availability_zone

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port      = local.bastion_vm.ssh_port
  bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql
}

module "aws_vms" {
  source   = "./modules/aws/vm"
  for_each = local.aws_vms

  name                 = "${local.resource_prefix}-${each.key}"
  management_subnet_id = module.aws_network[0].management_subnet_id
  workload_subnet_id   = module.aws_network[0].workload_subnet_id
  security_group_ids   = module.aws_network[0].security_group_ids
  role                 = each.value.role
  instance_type        = each.value.native_vm_type
  ami                  = each.value.native_image
  internal_ip          = each.value.internal_ip
  boot_disk_size_gb    = each.value.disk_size_gb
  boot_disk_type       = each.value.native_disk_type
  assign_public_ip     = each.value.assign_public_ip
  ssh_users            = local.config.ssh_users
  ssh_port             = lookup(each.value, "ssh_port", 22)

  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    { role = each.value.role },
  )
}
