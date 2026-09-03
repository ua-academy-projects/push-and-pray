resource "aws_iam_role" "workload_instance_role" {
  name = local.vm_names[each.key]

  for_each = var.vms

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = local.instance_tags_by_vm[each.key]
}

resource "aws_iam_instance_profile" "workload_profile" {
  name = local.vm_names[each.key]

  for_each = var.vms

  role = aws_iam_role.workload_instance_role[each.key].name
}

data "aws_ami" "ubuntu" {
  for_each    = var.vms
  most_recent = true

  filter {
    name   = "name"
    values = [each.value.image_config.name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = each.value.image_config.owners
}

resource "aws_instance" "workload" {
  for_each = var.vms

  ami = data.aws_ami.ubuntu[each.key].id

  instance_type = each.value.instance_type

  subnet_id = local.subnet_ids_by_vm[each.key]

  vpc_security_group_ids = [
    var.security_group_ids[each.value.role]
  ]
  private_ip = each.value.internal_ip

  associate_public_ip_address = each.value.assign_public_ip

  iam_instance_profile = aws_iam_instance_profile.workload_profile[each.key].name

  tags = local.instance_tags_by_vm[each.key]

  key_name = var.key_name

  root_block_device {
    volume_size = each.value.boot_disk.size_gb
    volume_type = each.value.disk_type
  }
  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["bastion", "ui"], each.value.role)
      error_message = "Only workloads with role bastion or ui may receive a public IP."
    }
  }
}
