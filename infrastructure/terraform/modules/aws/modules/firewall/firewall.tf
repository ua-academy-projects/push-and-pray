resource "aws_security_group" "scope" {
  for_each = toset(local.scopes)

  name        = "${var.resource_prefix}-${replace(each.value, "_", "-")}"
  description = "Traffic allowed to the ${each.value} scope"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-${replace(each.value, "_", "-")}" })
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  for_each = aws_security_group.scope

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion.allowed_cidrs)

  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = var.bastion.ssh_port
  to_port     = var.bastion.ssh_port

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = (
    var.enable_bastion_ssh_bootstrap && var.bastion.ssh_port != 22
    ? toset(var.bastion.allowed_cidrs)
    : toset([])
  )

  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  tags = var.tags
}

# Direct WireGuard connections between tailnet devices. Without it Tailscale
# still works, relayed through DERP and noticeably slower.
resource "aws_vpc_security_group_ingress_rule" "bastion_tailscale" {
  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = "0.0.0.0/0"

  ip_protocol = "udp"
  from_port   = var.tailscale.port
  to_port     = var.tailscale.port

  tags = var.tags
}

# A packet a node sends to another cloud or to the tailnet is routed to the
# bastion's network interface, and its security group checks it on the way in
# - addressed to someone else, but arriving at the bastion all the same.
resource "aws_vpc_security_group_ingress_rule" "bastion_forwarding" {
  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = var.network_cidr
  ip_protocol       = "-1"

  tags = var.tags
}

# Ansible reaches the nodes over the tailnet, which arrives with a tailnet
# source address; from the bastion itself it is the fallback.
resource "aws_vpc_security_group_ingress_rule" "node_ssh_bastion" {
  for_each = toset(local.node_scopes)

  security_group_id            = aws_security_group.scope[each.value].id
  referenced_security_group_id = aws_security_group.scope["bastion"].id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "node_ssh_tailnet" {
  for_each = toset(local.node_scopes)

  security_group_id = aws_security_group.scope[each.value].id
  cidr_ipv4         = var.tailscale.address_range

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "cluster" {
  for_each = local.cluster_rules

  security_group_id = aws_security_group.scope[each.value.scope].id
  cidr_ipv4         = each.value.cidr

  ip_protocol = each.value.protocol
  from_port   = each.value.port
  to_port     = each.value.port

  tags = merge(var.tags, { Name = each.value.name })
}

# Path MTU discovery needs ICMP: the tunnel between the clouds carries smaller
# packets than the networks on either side, and without "fragmentation
# needed" coming back large packets vanish silently. It also makes ping work.
resource "aws_vpc_security_group_ingress_rule" "cluster_icmp" {
  for_each = local.icmp_rules

  security_group_id = aws_security_group.scope[each.value.scope].id
  cidr_ipv4         = each.value.cidr

  ip_protocol = "icmp"
  from_port   = -1
  to_port     = -1

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ingress_web" {
  for_each = toset([for port in var.cluster.ingress.public_ports : tostring(port)])

  security_group_id = aws_security_group.scope["ingress"].id
  cidr_ipv4         = "0.0.0.0/0"

  ip_protocol = "tcp"
  from_port   = tonumber(each.value)
  to_port     = tonumber(each.value)

  tags = var.tags
}
