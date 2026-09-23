output "connection" {
  description = "Non-secret PostgreSQL connection settings for Ansible."
  value = {
    host               = aws_db_instance.main.address
    port               = aws_db_instance.main.port
    name               = aws_db_instance.main.db_name
    username           = aws_db_instance.main.username
    ssl_mode           = var.config.services.database.ssl_mode
    password_secret_id = var.config.services.database.password_secret_id
  }
}
