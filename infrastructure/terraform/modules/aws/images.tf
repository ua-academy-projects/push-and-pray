data "aws_ami" "vm" {
  for_each = local.vms

  most_recent = true
  owners      = each.value.image.owners

  filter {
    name   = "name"
    values = [each.value.image.name_pattern]
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