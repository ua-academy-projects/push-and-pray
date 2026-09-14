resource "aws_security_group" "bastion" {
  count = local.enabled ? 1 : 0

  name        = "${local.resource_prefix}-bastion-sg"
  description = "Allows inbound SSH"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description = "Allow SSH"
    from_port   = var.config.vms.bastion.ssh_port
    to_port     = var.config.vms.bastion.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.config.vms.bastion.allowed_cidrs
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "fetcher" {
  count = local.enabled ? 1 : 0

  name        = "${local.resource_prefix}-fetcher-sg"
  description = "Allows SSH from bastion"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion[0].id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ui" {
  count = local.enabled ? 1 : 0

  name        = "${local.resource_prefix}-ui-sg"
  description = "Allows bastion SSH and all HTTP/HTTPS"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion[0].id]
  }

  dynamic "ingress" {
    for_each = local.ui_public_ports
    content {
      description = "Allow inbound user traffic"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database" {
  count = local.enabled ? 1 : 0

  name        = "${local.resource_prefix}-database-sg"
  description = "Allows bastion SSH and connections from other VMs"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion[0].id]
  }

  ingress {
    description = "Allow a connection from other VMs"
    from_port   = var.config.service_ports.postgresql
    to_port     = var.config.service_ports.postgresql
    protocol    = "tcp"
    security_groups = [
      aws_security_group.fetcher[0].id,
      aws_security_group.history[0].id,
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "history" {
  count = local.enabled ? 1 : 0

  name        = "${local.resource_prefix}-history-sg"
  description = "Allows SSH from bastion and inbound from UI"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description     = "RabbitMQ TLS from Fetcher and History"
    from_port       = var.config.rabbitmq.port
    to_port         = var.config.rabbitmq.port
    protocol        = "tcp"
    security_groups = [aws_security_group.fetcher[0].id]
    self            = true
  }

  ingress {
    description     = "Allows SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion[0].id]
  }

  ingress {
    description     = "Allows inbound from UI"
    from_port       = var.config.service_ports.history_api
    to_port         = var.config.service_ports.history_api
    protocol        = "tcp"
    security_groups = [aws_security_group.ui[0].id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
