resource "aws_vpc_security_group_ingress_rule" "from_bastion" {
  for_each = local.bastion_ports

  security_group_id            = aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id
  referenced_security_group_id = var.bastion_security_group_id
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  ip_protocol                  = "tcp"
}
