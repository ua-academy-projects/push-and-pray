resource "aws_eip" "public" {
    for_each = local.public_vms
    domain = "vpc"
}
