output "endpoint" {
    value = try(aws_db_instance.main[0].address, null)
}