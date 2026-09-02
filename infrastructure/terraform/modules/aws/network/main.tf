resource "aws_vpc" "main" {
  for_each = local.instances

  region               = local.location.region
  cidr_block           = var.config.network.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.config.common_labels, { Name = "${local.resource_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  for_each = local.instances

  region = local.location.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(var.config.common_labels, { Name = "${local.resource_prefix}-igw" })
}

resource "aws_subnet" "management" {
  for_each = local.instances

  region                  = local.location.region
  vpc_id                  = aws_vpc.main[each.key].id
  cidr_block              = var.config.network.management_subnet_cidr
  availability_zone       = local.location.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.config.common_labels, { Name = "${local.resource_prefix}-management" })
}

resource "aws_subnet" "workload" {
  for_each = local.instances

  region                  = local.location.region
  vpc_id                  = aws_vpc.main[each.key].id
  cidr_block              = var.config.network.workload_subnet_cidr
  availability_zone       = local.location.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.config.common_labels, { Name = "${local.resource_prefix}-workload" })
}

resource "aws_eip" "nat" {
  for_each = local.instances

  region = local.location.region
  domain = "vpc"
  tags   = merge(var.config.common_labels, { Name = "${local.resource_prefix}-nat-ip" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  for_each = local.instances

  region        = local.location.region
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.management[each.key].id
  tags          = merge(var.config.common_labels, { Name = "${local.resource_prefix}-nat" })
}

resource "aws_route_table" "management" {
  for_each = local.instances

  region = local.location.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(var.config.common_labels, { Name = "${local.resource_prefix}-management" })
}

resource "aws_route" "management_internet" {
  for_each = local.instances

  region                 = local.location.region
  route_table_id         = aws_route_table.management[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[each.key].id
}

resource "aws_route_table_association" "management" {
  for_each = local.instances

  region         = local.location.region
  subnet_id      = aws_subnet.management[each.key].id
  route_table_id = aws_route_table.management[each.key].id
}

resource "aws_route_table" "workload" {
  for_each = local.instances

  region = local.location.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(var.config.common_labels, { Name = "${local.resource_prefix}-workload" })
}

resource "aws_route" "workload_internet" {
  for_each = local.instances

  region                 = local.location.region
  route_table_id         = aws_route_table.workload[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[each.key].id
}

resource "aws_route_table_association" "workload" {
  for_each = local.instances

  region         = local.location.region
  subnet_id      = aws_subnet.workload[each.key].id
  route_table_id = aws_route_table.workload[each.key].id
}

resource "aws_security_group" "role" {
  for_each = local.vm_names_by_role

  region      = local.location.region
  name_prefix = "${local.resource_prefix}-${each.key}-"
  description = "OilScope ${each.key} role"
  vpc_id      = aws_vpc.main["this"].id

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-${each.key}"
    role = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "role" {
  for_each = local.vm_names_by_role

  region            = local.location.region
  security_group_id = aws_security_group.role[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(try(local.bastion_vm.allowed_cidrs, []))

  region            = local.location.region
  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = local.bastion_vm.ssh_port
  to_port           = local.bastion_vm.ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = (
    local.bastion_vm != null &&
    var.config.network.enable_bastion_ssh_bootstrap &&
    try(local.bastion_vm.ssh_port, 22) != 22
  ) ? toset(try(local.bastion_vm.allowed_cidrs, [])) : toset([])

  region            = local.location.region
  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.bastion_vm == null ? {} : local.workload_vm_roles

  region                       = local.location.region
  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role["bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = contains(local.roles, "ui") ? toset([for port in var.config.network.ui_public_ports : tostring(port)]) : toset([])

  region            = local.location.region
  security_group_id = aws_security_group.role["ui"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}
