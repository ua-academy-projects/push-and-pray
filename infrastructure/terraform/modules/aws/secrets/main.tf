resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_ids

  name        = each.value
  description = "OilScope deployment secret managed outside Terraform"
  tags        = var.tags
}
