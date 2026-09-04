locals {
  user_setup = join("\n", [
    for username, public_key in var.ssh_users : <<-SCRIPT
      id -u '${username}' >/dev/null 2>&1 || useradd --create-home --shell /bin/bash '${username}'
      install -d -m 0700 -o '${username}' -g '${username}' '/home/${username}/.ssh'
      printf '%s' '${base64encode(trimspace(public_key))}' | base64 -d > '/home/${username}/.ssh/authorized_keys'
      chown '${username}:${username}' '/home/${username}/.ssh/authorized_keys'
      chmod 0600 '/home/${username}/.ssh/authorized_keys'
      printf '%s ALL=(ALL) NOPASSWD:ALL\n' '${username}' > '/etc/sudoers.d/90-${username}'
      chmod 0440 '/etc/sudoers.d/90-${username}'
    SCRIPT
  ])

  nat_setup = var.enable_nat ? (
    <<-SCRIPT
    sysctl -w net.ipv4.ip_forward=1
    printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-oilscope-nat.conf
    iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables-save > /etc/iptables.rules
    cat > /etc/systemd/system/oilscope-nat.service <<'UNIT'
    [Unit]
    Description=OilScope bastion NAT
    After=network-online.target
    Wants=network-online.target
    [Service]
    Type=oneshot
    ExecStart=/sbin/iptables-restore /etc/iptables.rules
    RemainAfterExit=yes
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now oilscope-nat.service
    SCRIPT
  ) : ""
}

resource "aws_key_pair" "this" {
  key_name   = var.name
  public_key = trimspace(var.ssh_users[sort(keys(var.ssh_users))[0]])
  tags       = var.tags
}

resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name
  tags = var.tags
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.internal_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = aws_key_pair.this.key_name
  iam_instance_profile        = aws_iam_instance_profile.this.name
  source_dest_check           = !var.enable_nat

  user_data = <<-SCRIPT
    #!/bin/bash
    set -eu
    ${local.user_setup}
    ${local.nat_setup}
  SCRIPT

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = var.root_volume_type
    encrypted             = true
    delete_on_termination = true
    tags                  = var.tags
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = !var.assign_public_ip || contains(["ui", "bastion"], var.role)
      error_message = "Only ui and bastion roles may receive a public IP."
    }
    precondition {
      condition = (
        !var.free_tier_guardrails ||
        (contains(["gp2", "gp3"], var.root_volume_type) && var.root_volume_size_gb <= 30)
      )
      error_message = "AWS cost guardrails require gp2/gp3 and at most 30 GiB per root volume; account-level eligibility and aggregate usage must be checked separately."
    }
  }
}

resource "aws_eip" "this" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = merge(var.tags, { Name = "${var.name}-ip" })
}
