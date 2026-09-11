resource "aws_internet_gateway" "this" {
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "management" {
  subnet_id      = var.management_subnet_id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = var.public_subnet_id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "workload" {
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_route_table_association" "workload" {
  subnet_id      = var.workload_subnet_id
  route_table_id = aws_route_table.workload.id
}

resource "aws_route" "workload_egress_via_bastion" {
  count = var.enable_bastion_nat ? 1 : 0

  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = var.bastion_network_interface_id
}
