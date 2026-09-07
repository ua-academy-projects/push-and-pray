resource "aws_iam_role" "ec2_role" {
  for_each = local.aws_vms

  name = "${local.resource_prefix}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "workload" {
  for_each = local.aws_vms

  name = "${local.resource_prefix}-${each.key}"
  role = aws_iam_role.ec2_role[each.key].name
}

data "aws_ssm_parameter" "ami" {
  for_each = { for name, vm in local.aws_vms : name => vm if startswith(vm.native_image, "/") }

  name = each.value.native_image
}

resource "aws_instance" "workload" {
  for_each = local.aws_vms

  ami           = startswith(each.value.native_image, "/") ? data.aws_ssm_parameter.ami[each.key].value : each.value.native_image
  instance_type = each.value.native_vm_type

  subnet_id              = local.subnet_ids[each.key]
  private_ip             = each.value.internal_ip
  vpc_security_group_ids = [local.security_group_ids[each.key]]

  iam_instance_profile = aws_iam_instance_profile.workload[each.key].name

  root_block_device {
    volume_size = each.value.disk_size_gb
    volume_type = each.value.native_disk_type
    iops        = each.value.native_disk_type == "io2" ? 3000 : null
  }

  user_data = local.cloud_init_user_data

  tags = merge(
    local.vm_labels[each.key],
    { Name = "${local.resource_prefix}-${each.key}" },
  )
}

resource "aws_eip" "public" {
  for_each = { for name, vm in local.aws_vms : name => vm if vm.assign_public_ip }

  domain   = "vpc"
  instance = aws_instance.workload[each.key].id
}
