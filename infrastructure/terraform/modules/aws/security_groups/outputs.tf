output "security_group_ids" {
  value = {
    bastion    = try(aws_security_group.bastion[0].id, null)
    infra      = try(aws_security_group.infra[0].id, null)
    history    = try(aws_security_group.history[0].id, null)
    fetcher    = try(aws_security_group.fetcher[0].id, null)
    ui         = try(aws_security_group.ui[0].id, null)
    k3s_server = try(aws_security_group.k3s_server[0].id, null)
    k3s_agent  = try(aws_security_group.k3s_agent[0].id, null)
  }
}
