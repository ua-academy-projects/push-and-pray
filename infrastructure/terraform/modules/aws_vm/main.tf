resource "aws_instance" "vms" {
  for_each = local.vms

  ami                  = data.aws_ami.images[each.value.image].id
  instance_type        = var.config.sizes[each.value.machine_type].aws
  iam_instance_profile = each.value.role == "bastion" ? null : var.instance_profile_names[each.key]

  subnet_id                   = each.value.assign_public_ip ? var.network.management_subnet_id : var.network.vm_subnet_id
  private_ip                  = try(each.value.internal_ips.aws, each.value.internal_ip)
  vpc_security_group_ids      = [var.network.security_group_ids_by_role[each.value.role]]
  associate_public_ip_address = false

  user_data                   = "#cloud-config\n${yamlencode(local.cloud_config)}"
  user_data_replace_on_change = true

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = each.value.boot_disk.size_gb
    volume_type           = var.config.disk_types[each.value.boot_disk.type].aws
    iops                  = try(each.value.boot_disk.iops, null)
    tags                  = local.tags[each.key]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = local.tags[each.key]

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["bastion", "ui"], each.value.role)
      error_message = "Only VMs with role bastion or ui may receive a public IP."
    }

    precondition {
      condition = (
        !contains(["io1", "io2"], var.config.disk_types[each.value.boot_disk.type].aws) ||
        try(each.value.boot_disk.iops > 0, false)
      )
      error_message = "AWS io1/io2 boot disks require a positive boot_disk.iops value."
    }
  }
}

resource "aws_eip" "public" {
  for_each = {
    for name, vm in local.vms : name => vm
    if vm.assign_public_ip
  }

  domain   = "vpc"
  instance = aws_instance.vms[each.key].id
  tags = merge(local.tags[each.key], {
    Name = "${local.resource_prefix}-${each.key}-ip"
  })
}
