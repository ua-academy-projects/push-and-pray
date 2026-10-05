resource "aws_security_group" "role" {
  for_each = local.role_instances

  region      = local.locations[each.value.location].region
  name_prefix = "${local.resource_prefix}-${each.value.role}${local.location_suffixes[each.value.location]}-"
  description = "OilScope ${each.value.role} role"
  vpc_id      = aws_vpc.main[each.value.location].id

  tags = merge(local.labels, {
    Name = "${local.resource_prefix}-${each.value.role}${local.location_suffixes[each.value.location]}"
    role = each.value.role
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "role" {
  for_each = local.role_instances

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = local.bastion_cidrs

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.ssh_port
  to_port           = each.value.ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = local.bootstrap_bastion_cidrs

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  cidr_ipv4         = each.value.cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_role_instances

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "private_dashboards" {
  for_each = {
    for key, instance in local.role_instances : key => instance
    if instance.role == "k3s_server" && local.bastion_vms_by_location[instance.location] != null
  }

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  from_port                    = 30081
  to_port                      = 30082
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "k3s_api" {
  for_each = local.k3s_nodes

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.value.location == var.config.default_location ? "k3s_server" : "${each.value.location}/k3s_server"].id
  referenced_security_group_id = aws_security_group.role[each.key].id
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "k3s_etcd" {
  for_each = {
    for key, instance in local.role_instances : key => instance if instance.role == "k3s_server"
  }

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role[each.key].id
  from_port                    = 2379
  to_port                      = 2380
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "k3s_vxlan" {
  for_each = local.k3s_node_pairs

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.value.target_key].id
  referenced_security_group_id = aws_security_group.role[each.value.source_key].id
  from_port                    = 8472
  to_port                      = 8472
  ip_protocol                  = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "k3s_kubelet" {
  for_each = local.k3s_node_pairs

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.value.target_key].id
  referenced_security_group_id = aws_security_group.role[each.value.source_key].id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_postgresql" {
  for_each = {
    for key, instance in local.role_instances : key => instance
    if var.config.database_mode == "postgres_extensions" && contains(["k3s_server", "k3s_agent"], instance.role) && contains(
      keys(local.role_instances),
      instance.location == var.config.default_location ? "k3s_server" : "${instance.location}/k3s_server"
    )
  }

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.value.location == var.config.default_location ? "k3s_server" : "${each.value.location}/k3s_server"].id
  referenced_security_group_id = aws_security_group.role[each.key].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_web" {
  for_each = local.ingress_ports

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? each.value.role : "${each.value.location}/${each.value.role}"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}
