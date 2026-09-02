data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = var.image_owners

  filter {
    name   = "name"
    values = [var.image_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_iam_role" "workload" {
  name = "${var.name}-role"

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

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-role"
    },
  )
}

resource "aws_iam_instance_profile" "workload" {
  name = "${var.name}-profile"
  role = aws_iam_role.workload.name

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-profile"
    },
  )
}

resource "aws_instance" "workload" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]

  private_ip = var.private_ip

  iam_instance_profile = aws_iam_instance_profile.workload.name

  user_data = "#cloud-config\n${yamlencode({
    users = [
      for username, public_key in var.ssh_users : {
        name                = username
        groups              = ["sudo"]
        shell               = "/bin/bash"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = [trimspace(public_key)]
      }
    ]
    ssh_pwauth = false
  })}"

  associate_public_ip_address = false

  root_block_device {
    volume_size = var.boot_disk_size_gb
    volume_type = var.boot_disk_type
    encrypted   = true

    tags = merge(
      var.tags,
      {
        Name = "${var.name}-root"
      },
    )
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(
    var.tags,
    {
      Name = var.name
      role = var.role
    },
  )
}

resource "aws_eip" "public" {
  count = var.assign_public_ip ? 1 : 0

  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-public-ip"
    },
  )
}

resource "aws_eip_association" "public" {
  count = var.assign_public_ip ? 1 : 0

  allocation_id = aws_eip.public[0].id
  instance_id   = aws_instance.workload.id
}
