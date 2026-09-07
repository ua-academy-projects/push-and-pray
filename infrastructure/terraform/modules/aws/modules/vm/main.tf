resource "aws_eip" "public" {
  count = var.vm.assign_public_ip ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-ip" })
}

resource "aws_instance" "workload" {
  ami           = local.ami
  instance_type = local.instance_type

  subnet_id              = var.subnet_id
  private_ip             = var.vm.internal_ip
  vpc_security_group_ids = var.security_group_ids

  iam_instance_profile = var.instance_profile_name
  user_data            = local.user_data

  root_block_device {
    volume_size = var.vm.boot_disk.size_gb
    volume_type = local.boot_disk_type
    encrypted   = true

    tags = var.tags
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    precondition {
      condition     = !var.vm.assign_public_ip || contains(["ui", "bastion"], var.vm.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_eip_association" "public" {
  count = var.vm.assign_public_ip ? 1 : 0

  instance_id   = aws_instance.workload.id
  allocation_id = aws_eip.public[0].id
}
