resource "aws_vpc" "main" {
  cidr_block = var.profile.network_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.resource_prefix}-vpc" })
}

# The bastion, and anything else holding a public IP, lives here: reaching the
# internet from AWS needs a route to the gateway, not just an address.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.profile.subnets.management
  availability_zone = var.profile.zone

  tags = merge(var.tags, { Name = "${var.resource_prefix}-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.profile.subnets.workload
  availability_zone = var.profile.zone

  tags = merge(var.tags, { Name = "${var.resource_prefix}-private" })
}

# RDS refuses a subnet group that does not span two availability zones, even
# for one instance that will only ever sit in one of them. So the database
# ranges take the first zones the region offers rather than the zone the VMs
# are pinned to.
data "aws_availability_zones" "available" {
  count = var.enable_database_subnets ? 1 : 0

  state = "available"
}

resource "aws_subnet" "database" {
  count = var.enable_database_subnets ? length(var.profile.subnets.database) : 0

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.profile.subnets.database[count.index]
  availability_zone = data.aws_availability_zones.available[0].names[count.index]

  tags = merge(var.tags, { Name = "${var.resource_prefix}-database-${count.index + 1}" })
}
