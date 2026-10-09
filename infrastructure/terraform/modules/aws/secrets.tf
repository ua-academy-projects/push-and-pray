locals {
  secret_version_managers = try(local.profile.secret_version_managers, [])

  secret_ids = module.selection.secret_ids

  # Only k3s_server nodes read secrets. Ansible resolves them there and hands
  # them on in memory: the join token to the agents, the Tailscale key to the
  # bastions, the rest into Kubernetes Secrets.
  server_nodes = [for name, node in local.nodes : name if node.role == "k3s_server"]
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.secret_ids)

  name        = each.value
  description = "Managed by Terraform from the cluster configuration"

  tags = local.common_tags
}

# GCP grants the reader on the secret; AWS grants the secret to the reader.
# Same least-privilege result reached from the opposite end: one inline policy
# per server node, naming every secret this cloud holds.
resource "aws_iam_role_policy" "secret_access" {
  for_each = length(local.secret_ids) > 0 ? toset(local.server_nodes) : toset([])

  name = "${local.resource_prefix}-${each.key}-secret-access"
  role = module.identity[each.key].role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [for secret in aws_secretsmanager_secret.this : secret.arn]
    }]
  })
}

# The counterpart of roles/secretmanager.secretVersionAdder: PutSecretValue
# without GetSecretValue, so a version can be written but never read back. The
# principals come from this cloud's profile, because each provider names one its
# own way.
#
# Keyed by the secret IDs from the configuration rather than by the secret
# resources themselves: for_each needs its keys at plan time, and a map built
# from resources is unknown until they exist.
resource "aws_secretsmanager_secret_policy" "version_adders" {
  for_each = length(local.secret_version_managers) > 0 ? toset(local.secret_ids) : toset([])

  secret_arn = aws_secretsmanager_secret.this[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = local.secret_version_managers }
      Action    = ["secretsmanager:PutSecretValue"]
      Resource  = "*"
    }]
  })
}
