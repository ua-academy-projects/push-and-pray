resource "aws_vpc" "main" {
    count = var.has_selected_vms ? 1 : 0

    cidr_block = var.vpc_cidr_block

    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
        Name = "${local.resource_prefix}-vpc"
    }
}

resource "aws_subnet" "management" {
    count = var.has_selected_vms ? 1 : 0

    vpc_id = aws_vpc.main[0].id
    cidr_block = var.config.network.management_subnet_cidr
    availability_zone = local.az

    tags = {
        Name = "${local.resource_prefix}-management"
    }
}

resource "aws_subnet" "workload" {
    count = var.has_selected_vms ? 1 : 0

    vpc_id = aws_vpc.main[0].id
    cidr_block = var.config.network.workload_subnet_cidr
    availability_zone = local.az

    tags = {
        Name = "${local.resource_prefix}-workload"
    }
}

