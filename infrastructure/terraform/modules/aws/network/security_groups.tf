resource "aws_security_group" "kubernetes" {
  count = local.enabled ? 1 : 0

  name        = "${var.config.name_prefix}-${var.config.environment}-kubernetes-sg"
  description = "Access to k3s nodes"
  vpc_id      = aws_vpc.main[0].id

  dynamic "ingress" {
    for_each = [22, 6443]

    content {
      description = "Administrator access"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.config.kubernetes.admin_allowed_cidrs
    }
  }

  dynamic "ingress" {
    for_each = [6443, 2379, 2380, 10250]

    content {
      description = "Cluster node communication"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      self        = true
    }
  }

  ingress {
    description = "Flannel VXLAN between nodes"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  dynamic "ingress" {
    for_each = var.config.network.ui_public_ports

    content {
      description = "Public application ingress"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Outbound access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
