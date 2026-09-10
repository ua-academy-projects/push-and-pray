resource "aws_key_pair" "bootstrap" {
  for_each = local.key_pair_locations

  region     = each.value.region
  key_name   = "${local.resource_prefix}-bootstrap${each.key == var.config.default_location ? "" : "-${each.key}"}"
  public_key = trimspace(one(values(var.config.ssh_users)))
  tags       = merge(var.config.common_labels, { environment = var.config.environment, Name = "${local.resource_prefix}-bootstrap" })
}

resource "terraform_data" "bootstrap_key" {
  for_each = local.vms

  input = aws_key_pair.bootstrap[each.value.location].public_key
}

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

resource "aws_cloudwatch_log_group" "system" {
  for_each = local.vms

  region = var.config.locations[each.value.location].aws.region
  name   = "/${local.resource_prefix}-${each.key}/system"
  tags   = local.labels_by_vm[each.key]
}

data "aws_iam_policy_document" "cloudwatch_agent" {
  count = length(local.vms) > 0 ? 1 : 0

  statement {
    sid       = "PublishHostMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CWAgent"]
    }
  }

  statement {
    sid       = "DescribeSystemLogStreams"
    actions   = ["logs:DescribeLogStreams"]
    resources = [for log_group in values(aws_cloudwatch_log_group.system) : trimsuffix(log_group.arn, ":*")]
  }

  statement {
    sid = "PublishSystemLogEvents"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      for log_group in values(aws_cloudwatch_log_group.system) :
      "${trimsuffix(log_group.arn, ":*")}:*"
    ]
  }
}

resource "aws_iam_policy" "cloudwatch_agent" {
  count = length(local.vms) > 0 ? 1 : 0

  name        = "${local.resource_prefix}-cloudwatch-agent"
  description = "Allow OilScope VMs to publish host metrics and system logs to CloudWatch"
  policy      = data.aws_iam_policy_document.cloudwatch_agent[0].json
  tags        = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = local.vms

  role       = aws_iam_role.workload[each.key].name
  policy_arn = aws_iam_policy.cloudwatch_agent[0].arn
}

#trivy:ignore:AVD-AWS-0028[associate_public_ip_address=true]
resource "aws_instance" "workload" {
  for_each = local.vms

  region                 = var.config.locations[each.value.location].aws.region
  ami                    = data.aws_ssm_parameter.image[each.key].value
  instance_type          = var.config.provider_mappings.instance_types[each.value.size].aws.instance_type
  subnet_id              = (each.value.role == "bastion" || each.value.assign_public_ip) ? var.management_subnet_ids[each.value.location] : var.workload_subnet_ids[each.value.location]
  private_ip             = each.value.internal_ip
  vpc_security_group_ids = [var.security_group_ids_by_location[each.value.location][each.value.role]]
  iam_instance_profile   = aws_iam_instance_profile.workload[each.key].name
  key_name               = aws_key_pair.bootstrap[each.value.location].key_name

  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = try(each.value.disk_size, null)
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
    replace_triggered_by = [
      terraform_data.bootstrap_key[each.key],
    ]

    ignore_changes = [
      associate_public_ip_address,
      user_data,
      user_data_replace_on_change,
    ]

    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }
}

resource "aws_ebs_volume" "data" {
  for_each = local.data_disks

  region            = var.config.locations[each.value.location].aws.region
  availability_zone = var.config.locations[each.value.location].aws.availability_zone
  size              = each.value.disk_size
  type              = var.config.provider_mappings.disk_types[each.value.disk_type].aws
  encrypted         = true
  tags = merge(
    local.labels_by_vm[each.value.vm_name],
    {
      Name = "${local.resource_prefix}-${each.key}"
    },
  )
}

resource "aws_volume_attachment" "data" {
  for_each = local.data_disks

  region      = var.config.locations[each.value.location].aws.region
  device_name = format("/dev/sd%c", each.value.disk_index + 101)
  volume_id   = aws_ebs_volume.data[each.key].id
  instance_id = aws_instance.workload[each.value.vm_name].id
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
