data "aws_ami" "ubuntu" {
  for_each = local.resolved_vms

  most_recent = true
  owners      = each.value.image_settings.owners

  filter {
    name   = "name"
    values = [each.value.image_settings.name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.resolved_vms

  name = "${each.value.name}-role"

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

  tags = merge(
    each.value.labels,
    {
      Name = "${each.value.name}-role"
    },
  )
}

resource "aws_iam_instance_profile" "workload" {
  for_each = local.resolved_vms

  name = "${each.value.name}-profile"
  role = aws_iam_role.workload[each.key].name

  tags = merge(
    each.value.labels,
    {
      Name = "${each.value.name}-profile"
    },
  )
}

resource "aws_instance" "workload" {
  for_each = local.resolved_vms

  lifecycle {
    # Resolve current AMIs for new instances; OS upgrades of existing VMs are explicit.
    ignore_changes = [ami]

    precondition {
      condition     = each.value.boot_disk.size_gb >= 8
      error_message = "boot_disk_size_gb must be at least 8 GiB."
    }
    precondition {
      condition     = contains(["gp2", "gp3"], each.value.disk_type)
      error_message = "AWS boot disks support gp2 or gp3 with provider-default performance; provisioned-IOPS disks are not supported."
    }
    precondition {
      condition     = contains(["bastion", "database", "history", "fetcher", "ui"], each.value.role)
      error_message = "role must be bastion, database, history, fetcher, or ui."
    }
    precondition {
      condition = length(each.value.image_settings.owners) > 0 && alltrue([
        for owner in each.value.image_settings.owners : can(regex("^[0-9]{12}$", owner))
      ])
      error_message = "image_owners must contain at least one valid 12-digit AWS account ID."
    }

    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", each.value.name))
      error_message = "VM names must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
    }
    precondition {
      condition     = startswith(each.value.provider_zone, "${each.value.provider_region}")
      error_message = "Every provider zone must belong to its resolved provider region."
    }
  }

  ami           = data.aws_ami.ubuntu[each.key].id
  instance_type = each.value.machine_type

  subnet_id              = contains(["bastion", "ui"], each.value.role) ? var.network.management_subnet_id : var.network.workload_subnet_id
  vpc_security_group_ids = [var.network.security_group_ids[each.value.role]]

  iam_instance_profile = aws_iam_instance_profile.workload[each.key].name

  user_data = "#cloud-config\n${yamlencode(merge({
    users = [
      for username, public_key in var.ssh_users : {
        name                = username
        groups              = ["sudo"]
        shell               = "/bin/bash"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = [trimspace(public_key)]
      }
    ]
    ssh_pwauth = false
    }, {
    write_files = lookup(var.startup_scripts, each.key, "") == "" ? [] : [{
      path        = "/usr/local/sbin/oilscope-bootstrap"
      owner       = "root:root"
      permissions = "0700"
      content     = var.startup_scripts[each.key]
    }]
    runcmd = lookup(var.startup_scripts, each.key, "") == "" ? [] : [["/usr/local/sbin/oilscope-bootstrap"]]
  }))}"

  associate_public_ip_address = false

  root_block_device {
    volume_size = each.value.boot_disk.size_gb
    volume_type = each.value.disk_type
    encrypted   = true

    tags = merge(
      each.value.labels,
      {
        Name = "${each.value.name}-root"
      },
    )
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(
    each.value.labels,
    {
      Name = each.value.name
      role = each.value.role
    },
  )
}

resource "aws_eip" "public" {
  for_each = local.public_vms

  domain = "vpc"

  tags = merge(
    each.value.labels,
    {
      Name = "${each.value.name}-public-ip"
    },
  )
}

resource "aws_eip_association" "public" {
  for_each = local.public_vms

  allocation_id = aws_eip.public[each.key].id
  instance_id   = aws_instance.workload[each.key].id
}
