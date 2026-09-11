output "connection" {
  value = {
    host = aws_db_instance.this.address
    port = aws_db_instance.this.port
    name = aws_db_instance.this.db_name
    user = aws_db_instance.this.username
  }
}
