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

data "aws_ssm_parameter" "image" {
  name = var.image_ssm_parameter
}

resource "aws_iam_role" "workload" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "workload" {
  name = var.name
  role = aws_iam_role.workload.name
  tags = var.tags
}

resource "aws_instance" "workload" {
  ami                    = data.aws_ssm_parameter.image.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = var.internal_ip
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.workload.name
  key_name               = var.key_name

  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size_gb
    volume_type           = var.root_volume_type
    tags                  = var.tags
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [
      key_name,
      user_data,
      user_data_replace_on_change,
    ]

    precondition {
      condition     = !var.assign_public_ip || contains(["ui", "bastion"], var.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }
}

resource "aws_eip" "public" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.workload.id
  tags     = merge(var.tags, { Name = "${var.name}-ip" })
}
