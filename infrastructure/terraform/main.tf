
module "gcp_network" {
  source = "./modules/gcp/network"
  count  = local.has_gcp ? 1 : 0

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

  depends_on = [terraform_data.config_validation, google_project_service.required]
}

module "aws_network" {
  source = "./modules/aws/network"
  count  = local.has_aws ? 1 : 0

  resource_prefix   = local.resource_prefix
  availability_zone = local.zone["aws"]

  vpc_cidr               = local.config.network.vpc_cidr
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

  tags = local.common_labels

  depends_on = [terraform_data.config_validation]
}

moved {
  from = module.network
  to   = module.gcp_network[0]
}

moved {
  from = module.vm
  to   = module.gcp_vm
}

locals {
  network = {
    gcp = {
      management_subnet_id = one(module.gcp_network[*].management_subnet_id)
      workload_subnet_id   = one(module.gcp_network[*].workload_subnet_id)
      workload_groups      = one(module.gcp_network[*].workload_groups)
    }
    aws = {
      management_subnet_id = one(module.aws_network[*].management_subnet_id)
      workload_subnet_id   = one(module.aws_network[*].workload_subnet_id)
      workload_groups      = one(module.aws_network[*].workload_groups)
    }
  }
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "gcp_vm" {
  source   = "./modules/gcp/vm"
  for_each = local.gcp_vms

  name      = "${local.resource_prefix}-${each.key}"
  role      = each.value.role
  subnet_id = local.network[each.value.cloud]["${each.value.subnet}_subnet_id"]

  network_groups = [
    for tag in each.value.network_tags : local.network[each.value.cloud].workload_groups[tag]
  ]

  machine_type = each.value.machine_type
  image        = each.value.image
  internal_ip  = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk_type

  assign_public_ip = each.value.assign_public_ip
  ssh_users        = local.config.ssh_users

  labels = merge(
    local.common_labels,
    lookup(each.value, "labels", {}),
    {
      role = each.value.role
    },
  )

  depends_on = [terraform_data.config_validation, google_project_service.required]
}

module "aws_vm" {
  source   = "./modules/aws/vm"
  for_each = local.aws_vms

  name      = "${local.resource_prefix}-${each.key}"
  role      = each.value.role
  subnet_id = local.network[each.value.cloud]["${each.value.subnet}_subnet_id"]

  network_groups = [
    for tag in each.value.network_tags : local.network[each.value.cloud].workload_groups[tag]
  ]

  machine_type = each.value.machine_type
  image        = each.value.image
  internal_ip  = each.value.internal_ip

  boot_disk_size_gb = each.value.boot_disk.size_gb
  boot_disk_type    = each.value.boot_disk_type

  assign_public_ip = each.value.assign_public_ip
  ssh_users        = local.config.ssh_users

  labels = merge(
    local.common_labels,
    lookup(each.value, "labels", {}),
    {
      role = each.value.role
    },
  )

  depends_on = [terraform_data.config_validation]
}

locals {
  vm = merge(
    {
      for name, instance in module.gcp_vm : name => {
        name             = instance.name
        internal_ip      = instance.internal_ip
        public_ip        = instance.public_ip
        network_groups   = instance.network_groups
        runtime_identity = instance.runtime_identity
      }
    },
    {
      for name, instance in module.aws_vm : name => {
        name             = instance.name
        internal_ip      = instance.internal_ip
        public_ip        = instance.public_ip
        network_groups   = instance.network_groups
        runtime_identity = instance.runtime_identity
      }
    },
  )
}
