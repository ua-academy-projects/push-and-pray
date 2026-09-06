resource "aws_iam_role" "ec2_role" {
  name = var.name

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
  name = var.name
  role = aws_iam_role.ec2_role.name
}

resource "aws_eip" "public" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.workload.id
}

data "aws_ssm_parameter" "ami" {
  count = startswith(var.ami, "/") ? 1 : 0

  name = var.ami
}

resource "aws_instance" "workload" {
  ami           = startswith(var.ami, "/") ? data.aws_ssm_parameter.ami[0].value : var.ami
  instance_type = var.instance_type

  subnet_id              = local.subnet_id
  private_ip             = var.internal_ip
  vpc_security_group_ids = [local.security_group_id]

  iam_instance_profile = aws_iam_instance_profile.workload.name

  root_block_device {
    volume_size = var.boot_disk_size_gb
    volume_type = var.boot_disk_type
    iops        = var.boot_disk_type == "io2" ? 3000 : null
  }

  user_data = local.cloud_init_user_data

  tags = merge(var.labels, {
    Name = var.name
  })
}
