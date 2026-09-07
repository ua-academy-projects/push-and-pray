resource "aws_internet_gateway" "main" {
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-igw"
    }
}

resource "aws_eip" "nat" {
    domain = "vpc"

    tags = {
        Name = "${local.resource_prefix}-nat-eip"
    }
}

resource "aws_nat_gateway" "main" {
    allocation_id = aws_eip.nat.id
    subnet_id = var.management_subnet_id

    depends_on = [aws_internet_gateway.main]

    tags = {
        Name = "${local.resource_prefix}-nat"
    }
}

resource "aws_route_table" "public" {
    vpc_id = var.vpc_id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = {
        Name = "${local.resource_prefix}-public"
    }
}

resource "aws_route_table" "private" {
    vpc_id = var.vpc_id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.main.id
    }

    tags = {
        Name = "${local.resource_prefix}-private"
    }
}

resource "aws_route_table_association" "management" {
    subnet_id = var.management_subnet_id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "workload" {
    subnet_id = var.workload_subnet_id
    route_table_id = aws_route_table.private.id
}
