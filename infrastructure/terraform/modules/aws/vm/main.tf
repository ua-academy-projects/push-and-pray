resource "aws_iam_role" "node" {
  count = length(local.aws_vms) > 0 ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-node"

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
}

resource "aws_iam_instance_profile" "node" {
  count = length(local.aws_vms) > 0 ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-node"
  role = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_ebs_csi" {
  count = length(local.aws_vms) > 0 ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  for_each = local.aws_vms

  name = each.value.native_image
}

resource "aws_instance" "workload" {
  for_each = local.aws_vms

  ami           = data.aws_ssm_parameter.ami[each.key].value
  instance_type = each.value.native_vm_type
  monitoring    = try(var.config.monitoring.enabled, true) && try(var.config.monitoring.detailed_monitoring_enabled, false)

  subnet_id              = var.network.workload_subnet_id
  private_ip             = each.value.internal_ip
  vpc_security_group_ids = [var.network.security_group_ids[each.value.role]]

  iam_instance_profile = aws_iam_instance_profile.node[0].name

  root_block_device {
    volume_size = each.value.disk_size_gb
    volume_type = each.value.native_disk_type
    iops        = each.value.native_disk_type == "io2" ? 3000 : null
  }

  user_data = templatefile("${path.module}/../templates/ssh-users.yaml.tfpl", {
    ssh_users = var.config.ssh_users
  })

  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    try(each.value.labels, {}),
    { role = each.value.role },
    { for tag in each.value.network_tags : "${var.config.name_prefix}-${tag}" => "true" },
    { Name = "${var.config.name_prefix}-${var.config.environment}-${each.key}" },
  )
}

resource "aws_eip" "public" {
  for_each = { for name, vm in local.aws_vms : name => vm if vm.assign_public_ip }

  domain   = "vpc"
  instance = aws_instance.workload[each.key].id
}
