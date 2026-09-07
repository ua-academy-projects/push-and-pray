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