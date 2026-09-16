resource "aws_iam_role" "workload_instance_role" {
  name = local.vm_names[each.key]

  for_each = var.vms

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = local.instance_tags_by_vm[each.key]
}

resource "aws_iam_instance_profile" "workload_profile" {
  name = local.vm_names[each.key]

  for_each = var.vms

  role = aws_iam_role.workload_instance_role[each.key].name
}

# The CloudWatch Agent runs under the instance profile and uses IMDS
# credentials; no static AWS key is placed on a VM.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = var.vms

  role       = aws_iam_role.workload_instance_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# An instance receives only the secret ARNs declared by its own
# vms.<name>.secret_mappings entry. Bastion has no mappings and therefore no
# Secrets Manager read policy.
resource "aws_iam_role_policy" "secret_read" {
  for_each = {
    for name, secret_ids in var.secret_ids_by_vm :
    name => var.secret_arns_by_vm[name]
    if length(secret_ids) > 0
  }

  name = "${local.vm_names[each.key]}-secrets-read"
  role = aws_iam_role.workload_instance_role[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = each.value
      },
    ]
  })
}

data "aws_ami" "ubuntu" {
  for_each    = var.vms
  most_recent = true

  filter {
    name   = "name"
    values = [each.value.image_config.name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = each.value.image_config.owners
}

resource "aws_instance" "workload" {
  for_each = var.vms

  ami = data.aws_ami.ubuntu[each.key].id

  instance_type = each.value.instance_type

  subnet_id = local.subnet_ids_by_vm[each.key]

  vpc_security_group_ids = [
    var.security_group_ids[each.value.role]
  ]
  private_ip = each.value.internal_ip

  associate_public_ip_address = each.value.assign_public_ip

  # EC2 user data is consumed by cloud-init on the first boot. Replacing the
  # instance when the script changes keeps the SSH listener aligned with the
  # security group after a bastion port change.
  user_data = each.value.role == "bastion" ? templatefile(
    "${path.module}/templates/bastion-user-data.sh.tftpl",
    { ssh_port = var.bastion_ssh_port },
  ) : null
  user_data_replace_on_change = each.value.role == "bastion"

  # One-minute EC2 metrics allow CloudWatch alarms to honor the monitoring
  # configuration's minute-based durations.
  monitoring = true

  iam_instance_profile = aws_iam_instance_profile.workload_profile[each.key].name

  tags = local.instance_tags_by_vm[each.key]

  key_name = var.key_name

  root_block_device {
    volume_size = each.value.boot_disk.size_gb
    volume_type = each.value.disk_type
  }
  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["bastion", "ui"], each.value.role)
      error_message = "Only workloads with role bastion or ui may receive a public IP."
    }
  }
}
