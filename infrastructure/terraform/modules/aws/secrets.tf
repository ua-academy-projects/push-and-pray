locals {
  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) : values(workload.secret_mappings)
  ]))
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.all_secret_ids)

  name        = each.value
  description = "Managed by Terraform from the project configuration"

  tags = local.common_tags
}

# GCP grants the reader on the secret; AWS grants the secret to the reader.
# Same least-privilege result reached from the opposite end: one inline policy
# per workload, naming only the secrets that workload maps.
resource "aws_iam_role_policy" "secret_access" {
  for_each = {
    for name, workload in local.workload_vms : name => workload
    if length(workload.secret_mappings) > 0
  }

  name = "${local.resource_prefix}-${each.key}-secret-access"
  role = module.vm[each.key].iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        for secret_id in distinct(values(each.value.secret_mappings)) :
        aws_secretsmanager_secret.this[secret_id].arn
      ]
    }]
  })
}

# The counterpart of roles/secretmanager.secretVersionAdder: PutSecretValue
# without GetSecretValue, so a version can be written but never read back.
resource "aws_secretsmanager_secret_policy" "version_adders" {
  for_each = (
    length(var.secret_version_manager_arns) > 0
    ? aws_secretsmanager_secret.this
    : {}
  )

  secret_arn = each.value.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.secret_version_manager_arns }
      Action    = ["secretsmanager:PutSecretValue"]
      Resource  = "*"
    }]
  })
}
