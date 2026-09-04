locals {
  module_cloud = "aws"
  config       = jsondecode(file(var.project_config_path))
  cloud_config = lookup(local.config.clouds, local.module_cloud, {})
  defaults     = local.config.defaults

  selected_vms = {
    for name, vm in local.config.vms : name => vm
    if lower(lookup(vm, "cloud", local.config.default_cloud)) == local.module_cloud
  }

  effective_vms = {
    for name, vm in local.selected_vms : name => merge(vm, {
      instance_type = lookup(
        lookup(local.cloud_config, "machine_types", {}),
        lookup(vm, "machine_profile", local.defaults.machine_profile),
        null,
      )
      ami_id = lookup(
        lookup(local.cloud_config, "images", {}),
        lookup(vm, "image_profile", local.defaults.image_profile),
        null,
      )
      volume_type = lookup(
        lookup(local.cloud_config, "disk_types", {}),
        lookup(vm.boot_disk, "profile", local.defaults.disk_profile),
        null,
      )
    })
  }

  location = lookup(
    lookup(local.cloud_config, "locations", {}),
    local.defaults.location_profile,
    {},
  )

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"
  common_tags = merge(
    lookup(local.config, "common_labels", {}),
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.module_cloud
    }
  )

  bastions = {
    for name, vm in local.effective_vms : name => vm
    if vm.role == "bastion"
  }
  bastion_key = try(keys(local.bastions)[0], null)
  bastion     = try(values(local.bastions)[0], null)

  workload_vms = {
    for name, vm in local.effective_vms : name => vm
    if(
      vm.role != "bastion" &&
      vm.instance_type != null &&
      vm.ami_id != null &&
      vm.volume_type != null
    )
  }

  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) : values(workload.secret_mappings)
  ]))
}

resource "terraform_data" "configuration" {
  count = length(local.selected_vms) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(local.bastions) <= 1
      error_message = "AWS may contain at most one VM with role bastion."
    }
    precondition {
      condition     = try(local.location.zone, null) != null
      error_message = "defaults.location_profile must exist in clouds.aws.locations and define zone."
    }
  }
}

module "network" {
  source = "../aws_network"
  count  = length(local.selected_vms) > 0 ? 1 : 0

  resource_prefix        = local.resource_prefix
  vpc_cidr               = local.config.network.vpc_cidr
  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr
  public_subnet_cidr     = local.config.network.public_subnet_cidr
  availability_zone      = local.location.zone

  enable_bastion               = local.bastion != null
  bastion_ssh_port             = try(local.bastion.ssh_port, 22)
  bastion_allowed_cidrs        = try(local.bastion.allowed_cidrs, [])
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  ui_public_ports              = local.config.network.ui_public_ports
  history_api_port             = local.config.service_ports.history_api
  postgresql_port              = local.config.service_ports.postgresql
  tags                         = local.common_tags

  depends_on = [terraform_data.configuration]
}

module "vm" {
  source = "../aws_vm"
  for_each = {
    for name, vm in local.effective_vms : name => vm
    if vm.instance_type != null && vm.ami_id != null && vm.volume_type != null
  }

  name = "${local.resource_prefix}-${each.key}"
  role = each.value.role
  subnet_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : (
    each.value.assign_public_ip ? module.network[0].public_subnet_id : module.network[0].workload_subnet_id
  )
  security_group_ids  = [module.network[0].security_group_ids[each.value.role]]
  internal_ip         = each.value.internal_ip
  instance_type       = each.value.instance_type
  ami_id              = each.value.ami_id
  root_volume_size_gb = each.value.boot_disk.size_gb
  root_volume_type    = each.value.volume_type
  assign_public_ip    = each.value.assign_public_ip
  ssh_users           = local.config.ssh_users
  enable_nat = (
    each.value.role == "bastion" &&
    lookup(local.cloud_config, "bastion_nat", true)
  )
  free_tier_guardrails = lookup(local.cloud_config, "free_tier_guardrails", true)
  tags = merge(
    local.common_tags,
    lookup(each.value, "labels", {}),
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.module_cloud
      role        = each.value.role
      vm_name     = each.key
    },
  )

  depends_on = [terraform_data.configuration]
}

resource "aws_route" "workload_egress_via_bastion" {
  count = (
    local.bastion_key != null &&
    lookup(local.cloud_config, "bastion_nat", true)
  ) ? 1 : 0

  route_table_id         = module.network[0].workload_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.vm[local.bastion_key].primary_network_interface_id
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = {
    for name, vm in local.workload_vms : name => vm
    if length(vm.secret_mappings) > 0
  }

  name = "${local.resource_prefix}-secret-access"
  role = module.vm[each.key].iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = length(each.value.secret_mappings) == 0 ? [] : [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      Resource = [
        for secret_id in distinct(values(each.value.secret_mappings)) :
        "arn:*:ssm:*:*:parameter/${trimprefix(secret_id, "/")}"
      ]
    }]
  })
}
