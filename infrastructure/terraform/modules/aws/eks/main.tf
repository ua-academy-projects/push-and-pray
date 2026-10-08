data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.resource_prefix}-eks"
  oidc_host    = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  # EKS bootstrap access already grants cluster-admin to the IAM principal
  # that creates the cluster. The AWS API exposes that principal as an STS
  # assumed-role ARN, while project config correctly uses the stable IAM role
  # ARN; normalize it before creating explicit access entries.
  cluster_creator_principal_arn = try(
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${regex("^arn:aws:sts::[0-9]+:assumed-role/([^/]+)/", data.aws_caller_identity.current.arn)[0]}",
    data.aws_caller_identity.current.arn,
  )
  additional_administrator_principal_arns = toset([
    for principal_arn in var.settings.administrator_principal_arns : principal_arn
    if principal_arn != local.cluster_creator_principal_arn
  ])
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster_name}-cluster"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name               = "${local.cluster_name}-node"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.settings.version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.settings.public_access_cidrs
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  tags                      = var.tags
  depends_on                = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_access_entry" "administrator" {
  for_each      = local.additional_administrator_principal_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "administrator" {
  for_each      = local.additional_administrator_principal_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.administrator]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.settings.node_instance_type]
  capacity_type   = "ON_DEMAND"
  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  update_config {
    max_unavailable = 1
  }
  depends_on = [aws_iam_role_policy_attachment.node]
  tags       = var.tags
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_eks_addon" "this" {
  for_each                    = toset(["vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver", "amazon-cloudwatch-observability"])
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.this]
}

resource "aws_ecr_repository" "application" {
  for_each             = toset(["fetcher", "history", "ui", "database", "database-cnpg"])
  name                 = "${var.resource_prefix}/oilscope/${each.value}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = var.tags
}

resource "aws_acm_certificate" "ui" {
  domain_name       = var.settings.public_endpoint.hostname
  validation_method = "DNS"
  tags              = var.tags
}

resource "aws_cloudwatch_dashboard" "eks" {
  dashboard_name = "${local.cluster_name}-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "EKS control plane requests", view = "timeSeries", region = data.aws_region.current.region,
          metrics = [["AWS/EKS", "apiserver_request_total", "ClusterName", aws_eks_cluster.this.name]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "Container Insights node health", view = "timeSeries", region = data.aws_region.current.region,
          metrics = [["ContainerInsights", "cluster_failed_node_count", "ClusterName", aws_eks_cluster.this.name]]
        }
      }
    ]
  })
}
