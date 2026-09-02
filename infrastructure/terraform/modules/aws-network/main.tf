resource "aws_vpc" "main" {
  cidr_block           = var.network_config.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.resource_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-igw" })
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.network_config.management_subnet_cidr
  availability_zone       = var.location_config.aws.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.resource_prefix}-management" })
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.network_config.workload_subnet_cidr
  availability_zone       = var.location_config.aws.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-nat-ip" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.management.id
  tags          = merge(var.tags, { Name = "${var.resource_prefix}-nat" })
}

resource "aws_route_table" "management" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-management" })
}

resource "aws_route" "management_internet" {
  route_table_id         = aws_route_table.management.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.management.id
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_route" "workload_internet" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}

resource "aws_security_group" "role" {
  for_each = local.vm_names_by_role

  name_prefix = "${var.resource_prefix}-${each.key}-"
  description = "OilScope ${each.key} role"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-${each.key}"
    role = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "role" {
  for_each = local.vm_names_by_role

  security_group_id = aws_security_group.role[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(local.bastion_vm.allowed_cidrs)

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = local.bastion_vm.ssh_port
  to_port           = local.bastion_vm.ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = var.network_config.enable_bastion_ssh_bootstrap && local.bastion_vm.ssh_port != 22 ? toset(local.bastion_vm.allowed_cidrs) : toset([])

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = {
    for role, name in local.vm_names_by_role : role => name
    if role != "bastion"
  }

  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role["bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = toset([for port in var.network_config.ui_public_ports : tostring(port)])

  security_group_id = aws_security_group.role["ui"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}
