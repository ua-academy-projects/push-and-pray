resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name
  tags = var.tags
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = var.internal_ip
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.this.name
  source_dest_check      = !var.enable_nat
  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    ssh_users = var.ssh_users
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = var.root_volume_type
    encrypted             = true
    delete_on_termination = true
    tags                  = var.tags
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = !var.assign_public_ip || contains(["ui", "bastion"], var.role)
      error_message = "Only ui and bastion roles may receive a public IP."
    }
    precondition {
      condition = (
        !var.free_tier_guardrails ||
        (contains(["gp2", "gp3"], var.root_volume_type) && var.root_volume_size_gb <= 30)
      )
      error_message = "AWS cost guardrails require gp2/gp3 and at most 30 GiB per root volume; account-level eligibility and aggregate usage must be checked separately."
    }
  }
}

resource "aws_eip" "this" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = merge(var.tags, { Name = "${var.name}-ip" })
}
