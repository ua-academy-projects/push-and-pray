locals {
  workload_groups = {
    infra   = aws_security_group.infra.id
    history = aws_security_group.history.id
    fetcher = aws_security_group.fetcher.id
    ui      = aws_security_group.ui.id
  }
}
