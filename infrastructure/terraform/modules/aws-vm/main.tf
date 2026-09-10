data "aws_ssm_parameter" "image" {
  for_each = local.vms

  region = each.value.region
  name   = each.value.image.ssm_parameter
}

resource "aws_key_pair" "bootstrap" {
  for_each = var.networks

  region     = each.value.region
  key_name   = "${local.context.resource_prefix}-${each.key}-bootstrap"
  public_key = local.bootstrap_ssh_public_key

  tags = local.context.labels
}

resource "aws_instance" "this" {
  for_each = local.vms

  region                      = each.value.region
  ami                         = data.aws_ssm_parameter.image[each.key].value
  instance_type               = each.value.machine_type
  subnet_id                   = each.value.assign_public_ip ? var.networks[each.value.location].public_subnet_id : var.networks[each.value.location].private_subnet_id
  private_ip                  = each.value.internal_ip
  vpc_security_group_ids      = [for tag in each.value.tags : var.security_group_ids[each.value.location][tag]]
  iam_instance_profile        = var.instance_profiles[each.key]
  key_name                    = aws_key_pair.bootstrap[each.value.location].key_name
  user_data                   = each.value.cloud_init
  user_data_replace_on_change = each.value.cloud_init != null

  root_block_device {
    volume_size           = each.value.boot_disk.size_gb
    volume_type           = each.value.boot_disk.type
    iops                  = each.value.boot_disk.iops
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(each.value.labels, { Name = "${local.context.resource_prefix}-${each.key}" })
  }

  dynamic "ebs_block_device" {
    for_each = each.value.data_disks

    content {
      device_name           = ebs_block_device.value.device_name
      volume_size           = ebs_block_device.value.size_gb
      volume_type           = ebs_block_device.value.type
      iops                  = ebs_block_device.value.iops
      delete_on_termination = true
      encrypted             = true
      tags = merge(each.value.labels, {
        Name = "${local.context.resource_prefix}-${each.key}-${ebs_block_device.key}"
      })
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(each.value.labels, {
    Name           = "${local.context.resource_prefix}-${each.key}"
    FunctionalTags = join(",", sort(each.value.tags))
  })
}

resource "aws_eip" "public" {
  for_each = {
    for name, vm in local.vms : name => vm if vm.assign_public_ip
  }

  region   = each.value.region
  domain   = "vpc"
  instance = aws_instance.this[each.key].id
  tags     = merge(each.value.labels, { Name = "${local.context.resource_prefix}-${each.key}-ip" })
}
