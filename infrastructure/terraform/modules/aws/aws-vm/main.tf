data "aws_ssm_parameter" "image" {
  for_each = local.ssm_image_paths

  name = each.value
}

resource "aws_key_pair" "operator" {
  count = length(local.vms) > 0 ? 1 : 0

  key_name   = "${local.resource_prefix}-${replace(local.primary_ssh_user, "_", "-")}"
  public_key = var.config.ssh_users[local.primary_ssh_user]

  tags = local.common_tags
}

resource "aws_instance" "this" {
  for_each = local.resolved_vms

  ami                         = startswith(each.value.image, "/") ? data.aws_ssm_parameter.image[each.value.image].value : each.value.image
  instance_type               = each.value.machine_type
  subnet_id                   = contains(["bastion", "ui"], each.value.role) ? var.subnet_ids["management"] : var.subnet_ids["workload"]
  private_ip                  = each.value.internal_ip
  associate_public_ip_address = each.value.assign_public_ip
  key_name                    = aws_key_pair.operator[0].key_name
  iam_instance_profile        = var.instance_profile_name
  vpc_security_group_ids      = [var.security_group_ids[each.key]]

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = each.value.boot_disk.size_gb
    volume_type           = each.value.boot_disk.type
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(
    lookup(each.value, "labels", {}),
    local.common_tags,
    {
      Name             = "${local.resource_prefix}-${each.key}"
      role             = each.value.role
      database_mode    = var.database_runtime.mode
      database_cloud   = var.database_runtime.cloud
      database_host    = var.database_runtime.host
      database_port    = tostring(var.database_runtime.port)
      database_name    = var.database_runtime.name
      database_user    = var.database_runtime.username
      database_sslmode = var.database_runtime.sslmode
      database_secret  = var.database_runtime.secret_reference
      queue_backend    = var.database_runtime.queue_backend
      queue_host       = var.database_runtime.queue_host
      queue_port       = tostring(var.database_runtime.queue_port)
      queue_username   = var.database_runtime.queue_username
      queue_vhost      = var.database_runtime.queue_vhost
      queue_secret     = var.database_runtime.queue_secret_reference
    },
  )
}
