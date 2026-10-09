resource "aws_vpc" "main" {
  for_each = local.locations

  region               = each.value.region
  cidr_block           = local.cloud_network.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.labels, { Name = "${local.resource_prefix}-vpc${local.location_suffixes[each.key]}" })
}

resource "aws_subnet" "management" {
  for_each = local.locations

  region                  = each.value.region
  vpc_id                  = aws_vpc.main[each.key].id
  cidr_block              = local.cloud_network.management_subnet_cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.labels, { Name = "${local.resource_prefix}-management${local.location_suffixes[each.key]}" }, local.managed_kubernetes_enabled && each.key == var.config.default_location ? { "kubernetes.io/role/elb" = "1" } : {})
}

resource "aws_subnet" "workload" {
  for_each = local.locations

  region                  = each.value.region
  vpc_id                  = aws_vpc.main[each.key].id
  cidr_block              = local.managed_kubernetes_enabled && each.key == var.config.default_location ? cidrsubnet(local.cloud_network.workload_subnet_cidr, 1, 0) : local.cloud_network.workload_subnet_cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.labels, { Name = "${local.resource_prefix}-workload${local.location_suffixes[each.key]}" }, local.managed_kubernetes_enabled && each.key == var.config.default_location ? { "kubernetes.io/role/internal-elb" = "1" } : {})
}

data "aws_availability_zones" "kubernetes" {
  count  = local.managed_kubernetes_enabled ? 1 : 0
  region = local.locations[var.config.default_location].region
  state  = "available"
}

resource "aws_subnet" "kubernetes_secondary" {
  count = local.managed_kubernetes_enabled ? 1 : 0

  region                  = local.locations[var.config.default_location].region
  vpc_id                  = aws_vpc.main[var.config.default_location].id
  cidr_block              = cidrsubnet(local.cloud_network.workload_subnet_cidr, 1, 1)
  availability_zone       = element([for zone in data.aws_availability_zones.kubernetes[0].names : zone if zone != local.locations[var.config.default_location].availability_zone], 0)
  map_public_ip_on_launch = false
  tags                    = merge(local.labels, { Name = "${local.resource_prefix}-kubernetes-secondary", "kubernetes.io/role/internal-elb" = "1" })

  lifecycle {
    precondition {
      condition     = length([for zone in data.aws_availability_zones.kubernetes[0].names : zone if zone != local.locations[var.config.default_location].availability_zone]) > 0
      error_message = "EKS requires a second available zone in the default AWS region."
    }
  }
}

data "aws_availability_zones" "database" {
  for_each = local.managed_database_enabled ? {
    (var.config.default_location) = local.locations[var.config.default_location]
  } : {}

  region = each.value.region
  state  = "available"
}

resource "aws_subnet" "database" {
  for_each = local.managed_database_enabled ? {
    for index, cidr in local.cloud_network.database_subnet_cidrs : tostring(index) => {
      cidr  = cidr
      index = index
    }
  } : {}

  region                  = local.locations[var.config.default_location].region
  vpc_id                  = aws_vpc.main[var.config.default_location].id
  cidr_block              = each.value.cidr
  availability_zone       = data.aws_availability_zones.database[var.config.default_location].names[each.value.index]
  map_public_ip_on_launch = false

  tags = merge(local.labels, {
    Name = "${local.resource_prefix}-database-${each.value.index + 1}"
  })

  lifecycle {
    precondition {
      condition     = length(data.aws_availability_zones.database[var.config.default_location].names) >= 2
      error_message = "Managed RDS requires at least two available zones in the default AWS region."
    }
  }
}
