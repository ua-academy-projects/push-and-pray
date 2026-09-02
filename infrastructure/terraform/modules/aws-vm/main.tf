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
  name = local.image_ssm_parameter
}

resource "aws_iam_role" "workload" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "workload" {
  name = local.name
  role = aws_iam_role.workload.name
  tags = local.tags
}

#trivy:ignore:AVD-AWS-0028[associate_public_ip_address=true]
resource "aws_instance" "workload" {
  ami                    = data.aws_ssm_parameter.image.value
  instance_type          = local.instance_type
  subnet_id              = local.subnet_id
  private_ip             = local.vm.internal_ip
  vpc_security_group_ids = local.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.workload.name
  key_name               = var.key_name

  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_type           = local.root_volume_type
    tags                  = local.tags
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.tags, { Name = local.name })

  lifecycle {
    ignore_changes = [
      key_name,
      user_data,
      user_data_replace_on_change,
    ]

    precondition {
      condition     = !local.vm.assign_public_ip || contains(["ui", "bastion"], local.vm.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }
}

resource "aws_eip" "public" {
  count = local.vm.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.workload.id
  tags     = merge(local.tags, { Name = "${local.name}-ip" })
}
