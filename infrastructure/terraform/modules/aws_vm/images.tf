data "aws_ami" "images" {
  for_each = toset([for vm in values(local.vms) : vm.image])

  most_recent = true
  owners      = var.config.images[each.value].aws.owners

  filter {
    name   = "name"
    values = [var.config.images[each.value].aws.name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
