resource "aws_vpc" "main" {
  cidr_block           = var.config.network.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-vpc"
  })
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.network.management_subnet_cidr
  availability_zone       = var.config.zones[var.config.location].aws
  map_public_ip_on_launch = false

  tags = merge(var.config.common_labels, {
    Name          = "${local.resource_prefix}-management"
    network_class = "management"
  })
}

resource "aws_subnet" "vm" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.network.workload_subnet_cidr
  availability_zone       = var.config.zones[var.config.location].aws
  map_public_ip_on_launch = false

  tags = merge(var.config.common_labels, {
    Name          = "${local.resource_prefix}-vm"
    network_class = "vm"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-igw"
  })
}