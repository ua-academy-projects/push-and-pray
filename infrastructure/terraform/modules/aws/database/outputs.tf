output "connection" {
  value = {
    host    = aws_db_instance.this.address
    port    = aws_db_instance.this.port
    name    = var.database_name
    user    = var.username
    sslmode = "require"
    security = {
      public_endpoint     = aws_db_instance.this.publicly_accessible
      transport_encrypted = true
    }
  }
}

output "identifier" {
  value = aws_db_instance.this.identifier
}
