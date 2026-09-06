resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "management" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.management_subnet_cidr
  availability_zone = var.availability_zone
}

resource "aws_subnet" "workload" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.workload_subnet_cidr
  availability_zone = var.availability_zone
}
