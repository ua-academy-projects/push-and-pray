output "name" { value = aws_instance.this.tags["Name"] }
output "internal_ip" { value = aws_instance.this.private_ip }
output "public_ip" { value = var.assign_public_ip ? aws_eip.this[0].public_ip : null }
output "network_tags" { value = [var.role] }
output "identity" { value = aws_iam_role.this.arn }
output "iam_role_name" { value = aws_iam_role.this.name }
output "primary_network_interface_id" { value = aws_instance.this.primary_network_interface_id }
