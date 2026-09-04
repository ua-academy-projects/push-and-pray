data "aws_iam_policy_document" "assume_role" {
  for_each = local.vms

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
  for_each = local.vms

  name   = var.config.provider_mappings.images[each.value.image].aws.ssm_parameter
  region = var.config.locations[each.value.location].aws.region
}

resource "aws_iam_role" "workload" {
  for_each = local.vms

  name               = "${local.resource_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json
  tags               = local.labels_by_vm[each.key]
}

resource "aws_iam_instance_profile" "workload" {
  for_each = local.vms

  name = "${local.resource_prefix}-${each.key}"
  role = aws_iam_role.workload[each.key].name
  tags = local.labels_by_vm[each.key]
}

#trivy:ignore:AVD-AWS-0028[associate_public_ip_address=true]
resource "aws_instance" "workload" {
  for_each = local.vms

  region                 = var.config.locations[each.value.location].aws.region
  ami                    = data.aws_ssm_parameter.image[each.key].value
  instance_type          = var.config.provider_mappings.instance_types[each.value.size].aws.instance_type
  subnet_id              = each.value.role == "bastion" ? var.management_subnet_ids[each.value.location] : var.workload_subnet_ids[each.value.location]
  private_ip             = each.value.internal_ip
  vpc_security_group_ids = [var.security_group_ids_by_location[each.value.location][each.value.role]]
  iam_instance_profile   = aws_iam_instance_profile.workload[each.key].name
  key_name               = var.key_names_by_location[each.value.location]

  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_type           = var.config.provider_mappings.disk_types[each.value.disk_type].aws
    tags                  = local.labels_by_vm[each.key]
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(
    local.labels_by_vm[each.key],
    {
      Name = "${local.resource_prefix}-${each.key}"
    },
  )

  lifecycle {
    ignore_changes = [
      key_name,
      user_data,
      user_data_replace_on_change,
    ]

    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }
}

resource "aws_eip" "public" {
  for_each = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  region   = var.config.locations[each.value.location].aws.region
  domain   = "vpc"
  instance = aws_instance.workload[each.key].id
  tags = merge(
    local.labels_by_vm[each.key],
    {
      Name = "${local.resource_prefix}-${each.key}-ip"
    },
  )
}
