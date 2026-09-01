resource "aws_iam_role" "workload_instance_role" {
  name = var.name

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

  tags = local.instance_tags
}

resource "aws_iam_instance_profile" "workload_profile" {
  name = var.name
  role = aws_iam_role.workload_instance_role.name
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "workload" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id = var.subnet_id
  vpc_security_group_ids = var.security_group_ids

  private_ip = var.private_ip

  associate_public_ip_address = var.assign_public_ip

  iam_instance_profile = aws_iam_instance_profile.workload_profile.name
  
  tags = local.instance_tags

  root_block_device {
    volume_size = var.boot_disk_size_gb
    volume_type = var.boot_disk_type
  }
  lifecycle {
    precondition {
      condition     = !var.assign_public_ip || contains(["bastion", "ui"], var.role)
      error_message = "Only workloads with role bastion or ui may receive a public IP."
    }
  }
}
