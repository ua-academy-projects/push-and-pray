data "aws_partition" "current" {}

resource "aws_iam_role" "cluster" {
  count = local.enabled ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = local.enabled ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  count = local.enabled ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.enabled ? toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryPullOnly",
  ]) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}
