resource "aws_secretsmanager_secret" "this" {
  for_each = local.all_secret_ids

  name = each.value

  tags = merge(local.common_tags, {
    Name = each.value
  })
}