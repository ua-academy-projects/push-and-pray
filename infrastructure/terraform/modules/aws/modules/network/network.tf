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
