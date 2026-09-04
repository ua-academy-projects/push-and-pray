resource "aws_instance" "main" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  iam_instance_profile = var.iam_instance_profile

  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = false

  user_data = templatefile(
    "${path.module}/templates/cloud-config.yaml.tftpl",
    {
      ssh_users = var.ssh_users
    },
  )

  user_data_replace_on_change = true

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.boot_disk_size_gb
    volume_type           = var.boot_disk_type

    tags = var.tags
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition = (
        !var.assign_public_ip ||
        contains(["bastion", "ui"], var.role)
      )
      error_message = "Only bastion and ui may receive public IP addresses."
    }
  }
}

resource "aws_eip" "public" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.main.id

  tags = merge(var.tags, {
    Name = "${var.name}-ip"
  })
}