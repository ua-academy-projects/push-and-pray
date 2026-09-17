module "config" {
  source              = "../config"
  project_config_path = var.project_config_path
  cloud               = "aws"
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

locals {
  ubuntu_lts_architectures = toset([
    for vm in values(module.config.provisionable_vms) : vm.architecture
    if vm.image == "ubuntu-lts"
  ])
}

data "aws_ami" "ubuntu_lts" {
  for_each = module.config.configuration_valid ? local.ubuntu_lts_architectures : toset([])

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${each.key}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [each.key == "arm64" ? "arm64" : "x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

module "network" {
  source = "./network"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? 1 : 0

  resource_prefix        = module.config.resource_prefix
  vpc_cidr               = module.config.network.vpc_cidr
  management_subnet_cidr = module.config.network.management_subnet_cidr
  workload_subnet_cidr   = module.config.network.workload_subnet_cidr
  public_subnet_cidr     = module.config.network.public_subnet_cidr
  availability_zone      = module.config.location.zone
  database_subnets = module.config.managed_database_enabled ? {
    for index, cidr in module.config.network.database_subnet_cidrs : tostring(index) => {
      cidr = cidr
      zone = module.config.network.database_availability_zones[index]
    }
  } : {}
  tags = module.config.common_metadata

  depends_on = [terraform_data.configuration]
}

module "security" {
  source = "./security"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? 1 : 0

  resource_prefix       = module.config.resource_prefix
  vpc_id                = module.network[0].vpc_id
  workload_subnet_cidr  = module.config.network.workload_subnet_cidr
  enable_bastion        = module.config.bastion != null
  enable_bastion_nat    = module.config.bastion != null && module.config.bastion_nat
  bastion_ssh_port      = try(module.config.bastion.ssh_port, 22)
  bastion_allowed_cidrs = try(module.config.bastion.allowed_cidrs, [])
  ui_public_ports       = module.config.network.ui_public_ports
  history_api_port      = module.config.config.service_ports.history_api
  postgresql_port       = module.config.config.service_ports.postgresql
  rabbitmq_port         = module.config.config.service_ports.rabbitmq
  redis_port            = module.config.config.service_ports.redis
  remote_workload_cidrs = toset(
    try(module.config.config.mixed_network.enabled, false) ? try([
      module.config.config.clouds.gcp.network.vpc_cidr
    ], []) : []
  )
  tags = module.config.common_metadata

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "database" {
  source = "./database"
  count  = module.config.managed_database_enabled && module.config.configuration_valid ? 1 : 0

  resource_prefix      = module.config.resource_prefix
  generation           = module.config.database.generation
  engine_version       = module.config.database.engine_version
  database_name        = module.config.database.database_name
  username             = module.config.database.username
  password             = var.database_password
  port                 = module.config.database.port
  instance_class       = module.config.database.aws.instance_class
  allocated_storage_gb = module.config.database.aws.allocated_storage_gb
  multi_az             = module.config.database.aws.multi_az
  backup_on_delete     = module.config.database.backup_on_delete
  backups_enabled      = module.config.database.backups_enabled
  deletion_protection  = module.config.database.deletion_protection
  snapshot_identifier  = try(module.config.database.restore.aws_snapshot_identifier, null)
  subnet_ids           = module.network[0].database_subnet_ids
  vpc_id               = module.network[0].vpc_id
  workload_security_group_ids = {
    for role in ["history", "fetcher", "ui"] :
    role => module.security[0].security_group_ids[role]
  }
  remote_workload_cidrs = toset(
    try(module.config.config.mixed_network.enabled, false) ? try([
      module.config.config.clouds.gcp.network.vpc_cidr
    ], []) : []
  )
  tags = module.config.common_metadata
}

resource "aws_ecr_repository" "application" {
  for_each = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? toset(["fetcher", "history", "ui", "database"]) : toset([])

  name                 = "${module.config.resource_prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = module.config.common_metadata
}

resource "aws_ecr_repository" "managed_service" {
  for_each = (
    module.config.manage_db &&
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? toset(["redis", "rabbitmq"]) : toset([])

  name                 = "${module.config.resource_prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = module.config.common_metadata
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
  security_group_ids = [module.security[0].security_group_ids[each.value.role]]
  internal_ip        = each.value.internal_ip
  instance_type      = each.value.machine_type
  ami_id = each.value.image == "ubuntu-lts" ? (
    data.aws_ami.ubuntu_lts[each.value.architecture].id
  ) : each.value.image
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

module "routing" {
  source = "./routing"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid
  ) ? 1 : 0

  resource_prefix      = module.config.resource_prefix
  vpc_id               = module.network[0].vpc_id
  management_subnet_id = module.network[0].management_subnet_id
  workload_subnet_id   = module.network[0].workload_subnet_id
  public_subnet_id     = module.network[0].public_subnet_id
  enable_bastion_nat   = module.config.bastion_key != null && module.config.bastion_nat
  bastion_network_interface_id = (
    module.config.bastion_key != null && module.config.bastion_nat
    ? module.vm[module.config.bastion_key].primary_network_interface_id
    : null
  )
  tags = module.config.common_metadata
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

resource "aws_iam_role_policy" "cloud_registry_pull" {
  for_each = {
    for name, vm in module.config.workload_vms : name => vm
    if module.config.configuration_valid
  }

  name = "${module.config.resource_prefix}-registry-pull"
  role = module.vm[each.key].iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = concat(
          [for repository in aws_ecr_repository.application : repository.arn],
          [for repository in aws_ecr_repository.managed_service : repository.arn],
        )
      },
    ]
  })
}

module "observability" {
  source = "./observability"
  count = (
    module.config.selected_count > 0 &&
    module.config.configuration_valid &&
    try(module.config.config.observability.enabled, false)
  ) ? 1 : 0

  resource_prefix    = module.config.resource_prefix
  region             = module.config.location.region
  alert_email        = module.config.config.observability.alert_email
  monthly_budget_usd = module.config.config.observability.monthly_budget_usd
  synthetic_url      = module.config.config.observability.synthetic_url
  log_retention_days = try(module.config.config.observability.log_retention_days, 14)
  http_5xx_threshold = try(module.config.config.observability.http_5xx_threshold, 1)
  http_5xx_window_seconds = try(
    module.config.config.observability.http_5xx_window_seconds,
    300,
  )
  tags                = module.config.common_metadata
  database_identifier = module.config.managed_database_enabled ? module.database[0].identifier : null
  database_enabled    = module.config.managed_database_enabled
  instances = {
    for name, vm in module.vm : name => {
      instance_id    = vm.instance_id
      iam_role_name  = vm.iam_role_name
      root_volume_id = vm.root_volume_id
    }
  }
}

moved {
  from = module.network[0].aws_internet_gateway.this
  to   = module.routing[0].aws_internet_gateway.this
}

moved {
  from = module.network[0].aws_route_table.public
  to   = module.routing[0].aws_route_table.public
}

moved {
  from = module.network[0].aws_route.public_internet
  to   = module.routing[0].aws_route.public_internet
}

moved {
  from = module.network[0].aws_route_table_association.management
  to   = module.routing[0].aws_route_table_association.management
}

moved {
  from = module.network[0].aws_route_table_association.public
  to   = module.routing[0].aws_route_table_association.public
}

moved {
  from = module.network[0].aws_route_table.workload
  to   = module.routing[0].aws_route_table.workload
}

moved {
  from = module.network[0].aws_route_table_association.workload
  to   = module.routing[0].aws_route_table_association.workload
}

moved {
  from = aws_route.workload_egress_via_bastion[0]
  to   = module.routing[0].aws_route.workload_egress_via_bastion[0]
}

moved {
  from = module.network[0].aws_security_group.role
  to   = module.security[0].aws_security_group.role
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.bastion_ssh
  to   = module.security[0].aws_vpc_security_group_ingress_rule.bastion_ssh
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.bastion_ssh_bootstrap
  to   = module.security[0].aws_vpc_security_group_ingress_rule.bastion_ssh_bootstrap
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.bastion_nat_from_workloads
  to   = module.security[0].aws_vpc_security_group_ingress_rule.bastion_nat_from_workloads
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.workload_ssh
  to   = module.security[0].aws_vpc_security_group_ingress_rule.workload_ssh
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.ui_web
  to   = module.security[0].aws_vpc_security_group_ingress_rule.ui_web
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.history_api
  to   = module.security[0].aws_vpc_security_group_ingress_rule.history_api
}

moved {
  from = module.network[0].aws_vpc_security_group_ingress_rule.postgresql
  to   = module.security[0].aws_vpc_security_group_ingress_rule.postgresql
}
