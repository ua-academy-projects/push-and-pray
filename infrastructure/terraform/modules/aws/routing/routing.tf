resource "aws_internet_gateway" "main" {
    count = var.has_selected_vms ? 1 : 0

    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-igw"
    }
}

resource "aws_eip" "nat" {
    count = var.has_selected_vms ? 1 : 0

    domain = "vpc"

    tags = {
        Name = "${local.resource_prefix}-nat-eip"
    }
}

resource "aws_nat_gateway" "main" {
    count = var.has_selected_vms ? 1 : 0

    allocation_id = aws_eip.nat[0].id
    subnet_id = var.management_subnet_id

    depends_on = [aws_internet_gateway.main]

    tags = {
        Name = "${local.resource_prefix}-nat"
    }
}

resource "aws_route_table" "public" {
    count = var.has_selected_vms ? 1 : 0

    vpc_id = var.vpc_id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main[0].id
    }

    tags = {
        Name = "${local.resource_prefix}-public"
    }
}

resource "aws_route_table" "private" {
    count = var.has_selected_vms ? 1 : 0

    vpc_id = var.vpc_id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.main[0].id
    }

    tags = {
        Name = "${local.resource_prefix}-private"
    }
}

resource "aws_route_table_association" "management" {
    count = var.has_selected_vms ? 1 : 0

    subnet_id = var.management_subnet_id
    route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "workload" {
    count = var.has_selected_vms ? 1 : 0

    subnet_id = var.workload_subnet_id
    route_table_id = aws_route_table.private[0].id
}
