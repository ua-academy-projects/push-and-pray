output "security_group_ids" {
  description = "Security groups indexed by workload role."

  value = {
    bastion  = aws_security_group.bastion.id
    database = aws_security_group.database.id
    history  = aws_security_group.history.id
    fetcher  = aws_security_group.fetcher.id
    ui       = aws_security_group.ui.id
  }
}

output "redis_ingress" {
  description = "Private Redis security-group rule metadata for validation and operations."
  value = {
    source_security_group_id = aws_vpc_security_group_ingress_rule.redis_from_ui.referenced_security_group_id
    target_security_group_id = aws_vpc_security_group_ingress_rule.redis_from_ui.security_group_id
    from_port                = aws_vpc_security_group_ingress_rule.redis_from_ui.from_port
    to_port                  = aws_vpc_security_group_ingress_rule.redis_from_ui.to_port
    cidr_ipv4                = aws_vpc_security_group_ingress_rule.redis_from_ui.cidr_ipv4
  }
}
