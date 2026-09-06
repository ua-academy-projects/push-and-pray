resource "aws_vpc" "main" {
  cidr_block = var.network_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.resource_prefix}-vpc" })
}

# The bastion, and anything else holding a public IP, lives here: reaching the
# internet from AWS needs a route to the gateway, not just an address.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(var.tags, { Name = "${var.resource_prefix}-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(var.tags, { Name = "${var.resource_prefix}-private" })
}
