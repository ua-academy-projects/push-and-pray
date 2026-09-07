output "security_group_ids" {
    value = {
        bastion = aws_security_group.bastion.id
        infra   = aws_security_group.infra.id
        history = aws_security_group.history.id
        fetcher = aws_security_group.fetcher.id
        ui      = aws_security_group.ui.id
    }
}
