resource "aws_security_group" "bastion" {
  name        = "${var.resource_prefix}-bastion-sg"
  description = "Allows inbound SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH"
    from_port   = var.bastion_ssh_port
    to_port     = var.bastion_ssh_port
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
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
  name        = "${var.resource_prefix}-fetcher-sg"
  description = "Allows SSH from bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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
  name        = "${var.resource_prefix}-ui-sg"
  description = "Allows bastion SSH and all HTTP/HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  dynamic "ingress" {
    for_each = var.ui_public_ports
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
  name        = "${var.resource_prefix}-database-sg"
  description = "Allows bastion SSH and connections from other VMs"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "Allow a connection from other VMs"
    from_port   = var.postgresql_port
    to_port     = var.postgresql_port
    protocol    = "tcp"
    security_groups = [aws_security_group.fetcher.id,
    aws_security_group.history.id, aws_security_group.ui.id]
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
  name        = "${var.resource_prefix}-history-sg"
  description = "Allows SSH from bastion and inbound from UI"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allows SSH from bastion"
    from_port       = "22"
    to_port         = "22"
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "Allows inbound from UI"
    from_port       = var.history_api_port
    to_port         = var.history_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ui.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
