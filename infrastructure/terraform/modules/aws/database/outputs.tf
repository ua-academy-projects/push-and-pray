output "connection" {
  value = {
    host = aws_db_instance.this.address
    port = aws_db_instance.this.port
    name = var.database_name
    user = var.username
  }
}

output "identifier" {
  value = aws_db_instance.this.identifier
}
