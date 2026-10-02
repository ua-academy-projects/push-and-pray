resource "aws_iam_role_policy" "node_pull" {
  count = local.enabled && try(var.vm.node_role_name, null) != null ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-node-registry-pull"
  role = var.vm.node_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = values(local.repository_arns)
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.enabled && local.publisher != null ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "publisher" {
  count = local.enabled && local.publisher != null ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-image-publisher"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.publisher}:ref:refs/tags/${var.config.registry.publish_tag_prefix}*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "publisher" {
  count = local.enabled && local.publisher != null ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-image-publisher"
  role = aws_iam_role.publisher[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = values(local.repository_arns)
      }
    ]
  })
}
