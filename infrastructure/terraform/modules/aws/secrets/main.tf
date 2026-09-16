resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_ids

  name        = each.value
  description = "OilScope deployment secret managed outside Terraform"
  tags        = var.tags
}

# Instance keys must be derived from non-sensitive IDs. The corresponding
# values remain sensitive and are never used as Terraform resource addresses.
resource "aws_secretsmanager_secret_version" "managed" {
  for_each = toset(nonsensitive(keys(var.secret_values)))

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = var.secret_values[each.key]
}
