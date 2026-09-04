module "config" {
  source = "./config"

  project_config_path = var.project_config_path
}

resource "terraform_data" "configuration" {
  count = module.config.selected_count > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = module.config.bastion_count <= 1
      error_message = "AWS may contain at most one VM with role bastion."
    }
  }
}

module "network" {
  source = "./network"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? 1 : 0

  resource_prefix        = module.config.resource_prefix
  vpc_cidr               = module.config.config.network.vpc_cidr
  management_subnet_cidr = module.config.config.network.management_subnet_cidr
  workload_subnet_cidr   = module.config.config.network.workload_subnet_cidr
  public_subnet_cidr     = module.config.config.network.public_subnet_cidr
  availability_zone      = module.config.location.zone

  enable_bastion               = module.config.bastion != null
  bastion_ssh_port             = try(module.config.bastion.ssh_port, 22)
  bastion_allowed_cidrs        = try(module.config.bastion.allowed_cidrs, [])
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  ui_public_ports              = module.config.config.network.ui_public_ports
  history_api_port             = module.config.config.service_ports.history_api
  postgresql_port              = module.config.config.service_ports.postgresql
  tags                         = module.config.common_metadata

  depends_on = [terraform_data.configuration]
}

module "vm" {
  source = "./vm"
  for_each = {
    for name, vm in module.config.provisionable_vms : name => vm
    if module.config.configuration_valid
  }

  name = "${module.config.resource_prefix}-${each.key}"
  role = each.value.role
  subnet_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : (
    each.value.assign_public_ip ? module.network[0].public_subnet_id : module.network[0].workload_subnet_id
  )
  security_group_ids  = [module.network[0].security_group_ids[each.value.role]]
  internal_ip         = each.value.internal_ip
  instance_type       = each.value.machine_type
  ami_id              = each.value.image
  root_volume_size_gb = each.value.boot_disk.size_gb
  root_volume_type    = each.value.disk_type
  assign_public_ip    = each.value.assign_public_ip
  ssh_users           = module.config.config.ssh_users
  enable_nat = (
    each.value.role == "bastion" &&
    module.config.bastion_nat
  )
  free_tier_guardrails = module.config.free_tier_guardrails
  tags                 = each.value.metadata

  depends_on = [terraform_data.configuration]
}

resource "aws_route" "workload_egress_via_bastion" {
  count = (
    module.config.configuration_valid &&
    module.config.bastion_key != null &&
    module.config.bastion_nat
  ) ? 1 : 0

  route_table_id         = module.network[0].workload_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.vm[module.config.bastion_key].primary_network_interface_id
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = {
    for name, vm in module.config.workload_vms : name => vm
    if module.config.configuration_valid && length(vm.secret_mappings) > 0
  }

  name = "${module.config.resource_prefix}-secret-access"
  role = module.vm[each.key].iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
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
