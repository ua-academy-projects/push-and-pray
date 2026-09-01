resource "aws_security_group" "bastion_ssh" {
  name   = "${var.resource_prefix}-allow-bastion-ssh"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "bastion-ssh"
  }

}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_to_bastion" {
  security_group_id = aws_security_group.bastion_ssh.id
  for_each          = toset(var.bastion_allowed_cidrs)
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = var.bastion_ssh_port
  to_port     = var.bastion_ssh_port

}

resource "aws_security_group" "ui" {
  name   = "${var.resource_prefix}-ui-security-group"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ui"
  }

}

resource "aws_vpc_security_group_ingress_rule" "allow_tls" {

  security_group_id = aws_security_group.ui.id
  for_each          = toset(var.ui_public_ports)
  from_port         = tonumber(each.value)
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  to_port           = tonumber(each.value)


}
resource "aws_security_group" "fetcher" {
  name   = "${var.resource_prefix}-fetcher-security-group"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "fetcher"
  }

}

resource "aws_security_group" "infra" {
  name   = "${var.resource_prefix}-infra-security-group"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "infra"
  }

}
resource "aws_security_group" "history" {
  name   = "${var.resource_prefix}-history-security-group"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "history"
  }

}

resource "aws_vpc_security_group_ingress_rule" "allow_bastion_ssh_to_infra" {
  security_group_id            = aws_security_group.infra.id
  referenced_security_group_id = aws_security_group.bastion_ssh.id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_bastion_ssh_to_history" {
  security_group_id            = aws_security_group.history.id
  referenced_security_group_id = aws_security_group.bastion_ssh.id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_bastion_ssh_to_ui" {
  security_group_id            = aws_security_group.ui.id
  referenced_security_group_id = aws_security_group.bastion_ssh.id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_bastion_to_fetcher" {
  security_group_id            = aws_security_group.fetcher.id
  referenced_security_group_id = aws_security_group.bastion_ssh.id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

}

resource "aws_vpc_security_group_ingress_rule" "allow_ui_to_history" {
  security_group_id            = aws_security_group.history.id
  referenced_security_group_id = aws_security_group.ui.id

  ip_protocol = "tcp"
  from_port   = var.history_api_port
  to_port     = var.history_api_port
}

resource "aws_vpc_security_group_ingress_rule" "allow_fetcher_to_infra" {
  security_group_id            = aws_security_group.infra.id
  referenced_security_group_id = aws_security_group.fetcher.id

  ip_protocol = "tcp"
  from_port   = var.postgresql_port
  to_port     = var.postgresql_port
}

resource "aws_vpc_security_group_ingress_rule" "allow_history_to_infra" {
  security_group_id            = aws_security_group.infra.id
  referenced_security_group_id = aws_security_group.history.id

  ip_protocol = "tcp"
  from_port   = var.postgresql_port
  to_port     = var.postgresql_port
}
resource "aws_vpc_security_group_ingress_rule" "allow_ui_to_infra" {
  security_group_id            = aws_security_group.infra.id
  referenced_security_group_id = aws_security_group.ui.id

  ip_protocol = "tcp"
  from_port   = var.postgresql_port
  to_port     = var.postgresql_port
}

resource "aws_vpc_security_group_ingress_rule" "allow_bootstrap_ssh_to_bastion" {
  for_each = (
    var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22
    ? toset(var.bastion_allowed_cidrs)
    : toset([])
  )

  security_group_id = aws_security_group.bastion_ssh.id
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_internet_egress" {
  for_each = {
    bastion  = aws_security_group.bastion_ssh.id
    database = aws_security_group.infra.id
    history  = aws_security_group.history.id
    fetcher  = aws_security_group.fetcher.id
    ui       = aws_security_group.ui.id
  }
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
