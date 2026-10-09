resource "aws_vpc" "main" {
  count = var.has_selected_vms ? 1 : 0

  cidr_block = var.vpc_cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.resource_prefix}-vpc"
  }
}

resource "aws_subnet" "management" {
  count = var.has_selected_vms ? 1 : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.config.network.management_subnet_cidr
  availability_zone = local.az

  tags = {
    Name = "${local.resource_prefix}-management"
  }
}

resource "aws_subnet" "workload" {
  count = var.has_selected_vms ? 1 : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.config.network.workload_subnet_cidr
  availability_zone = local.az

  tags = {
    Name = "${local.resource_prefix}-workload"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "database" {
  count = local.managed_db_enabled ? 2 : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 12, 10 + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.resource_prefix}-database-${count.index}"
  }
}

resource "aws_subnet" "kubernetes" {
  count = var.managed_kubernetes_enabled ? 1 : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, 20)
  availability_zone = local.kubernetes_secondary_az

  tags = {
    Name = "${local.resource_prefix}-kubernetes"
  }
}
