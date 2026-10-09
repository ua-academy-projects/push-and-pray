resource "aws_vpc" "main" {
  count = local.enabled ? 1 : 0

  cidr_block           = var.config.clouds.aws.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}


resource "aws_subnet" "workload" {
  count = local.enabled ? 1 : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.config.network.workload_subnet_cidr
  availability_zone       = var.config.region_map[var.config.region].aws.availability_zone
  map_public_ip_on_launch = local.eks_enabled

  tags = local.eks_enabled ? {
    "kubernetes.io/cluster/${var.config.name_prefix}-${var.config.environment}" = "shared"
    "kubernetes.io/role/elb"                                                    = "1"
  } : {}
}

resource "aws_subnet" "eks_secondary" {
  count = local.eks_enabled ? 1 : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.config.clouds.aws.eks_network.secondary_subnet_cidr
  availability_zone       = var.config.clouds.aws.eks_network.secondary_availability_zone
  map_public_ip_on_launch = true

  tags = {
    "kubernetes.io/cluster/${var.config.name_prefix}-${var.config.environment}" = "shared"
  }
}

resource "aws_subnet" "rds_primary" {
  count                   = local.rds_enabled ? 1 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.config.clouds.aws.rds_network.primary_subnet_cidr
  availability_zone       = var.config.region_map[var.config.region].aws.availability_zone
  map_public_ip_on_launch = false
}

resource "aws_subnet" "rds_secondary" {
  count                   = local.rds_enabled ? 1 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.config.clouds.aws.rds_network.secondary_subnet_cidr
  availability_zone       = var.config.clouds.aws.rds_network.secondary_availability_zone
  map_public_ip_on_launch = false
}
