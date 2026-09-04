output "name" {
  value = var.name
}

output "instance_id" {
  value = aws_instance.main.id
}

output "internal_ip" {
  value = aws_instance.main.private_ip
}

output "public_ip" {
  value = var.assign_public_ip ? aws_eip.public[0].public_ip : null
}