resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.resource_prefix}-vpc" })
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.management_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-management" })
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.workload_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-public" })
}

resource "aws_subnet" "database" {
  for_each = var.database_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-database-${each.key}" })
}
