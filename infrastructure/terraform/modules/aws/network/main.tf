resource "aws_vpc" "main" {
  count = local.enabled ? 1 : 0

  cidr_block           = var.config.clouds.aws.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "management" {
  count = local.enabled ? 1 : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.config.network.management_subnet_cidr
  availability_zone = local.availability_zone
}

resource "aws_subnet" "workload" {
  count = local.enabled ? 1 : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.config.network.workload_subnet_cidr
  availability_zone = local.availability_zone
}

resource "aws_subnet" "rds_secondary" {
  count                   = local.rds_enabled ? 1 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.config.clouds.aws.rds_network.secondary_subnet_cidr
  availability_zone       = var.config.clouds.aws.rds_network.secondary_availability_zone
  map_public_ip_on_launch = false
}
