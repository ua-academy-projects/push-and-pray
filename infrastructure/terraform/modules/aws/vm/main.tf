locals {
  iops_required = ["io1", "io2"]
}

data "aws_ami" "boot" {
  most_recent = true
  owners      = [var.image_owner]

  filter {
    name   = "name"
    values = [var.image]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  name               = var.name
  description        = "Runtime identity for the ${var.name} workload VM"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.labels
}

resource "aws_iam_instance_profile" "workload" {
  name = var.name
  role = aws_iam_role.workload.name

  tags = var.labels
}

resource "aws_instance" "workload" {
  ami           = data.aws_ami.boot.id
  instance_type = var.machine_type

  subnet_id              = var.subnet_id
  private_ip             = var.internal_ip
  vpc_security_group_ids = var.network_groups
  iam_instance_profile   = aws_iam_instance_profile.workload.name

  associate_public_ip_address = false

  root_block_device {
    volume_size = var.boot_disk_size_gb
    volume_type = var.boot_disk_type
    iops        = contains(local.iops_required, var.boot_disk_type) ? var.boot_disk_iops : null
    encrypted   = true

    tags = merge(var.labels, { Name = "${var.name}-root" })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/templates/ssh-users.yaml.tftpl", {
    ssh_users = var.ssh_users
  })

  lifecycle {
    precondition {
      condition     = !var.assign_public_ip || contains(["ui", "bastion"], var.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }

  tags = merge(var.labels, { Name = var.name })
}

resource "aws_eip" "public" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.workload.id

  tags = merge(var.labels, { Name = "${var.name}-ip" })
}
