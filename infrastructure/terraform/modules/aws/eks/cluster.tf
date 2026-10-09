resource "aws_eks_cluster" "this" {
  count = local.enabled ? 1 : 0

  name     = "${var.config.name_prefix}-${var.config.environment}"
  role_arn = aws_iam_role.cluster[0].arn
  version  = var.config.kubernetes.eks.version

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.network.eks_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = try(var.config.kubernetes.eks.public_api_access, true)
    public_access_cidrs = (
      try(var.config.kubernetes.eks.public_api_access, true)
      ? var.config.kubernetes.admin_allowed_cidrs
      : null
    )
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.config.kubernetes.service_cidr
  }

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_addon" "pod_identity" {
  count = local.enabled ? 1 : 0

  cluster_name = aws_eks_cluster.this[0].name
  addon_name   = "eks-pod-identity-agent"

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_eks_access_entry" "admin" {
  for_each = local.admin_principals

  cluster_name  = aws_eks_cluster.this[0].name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = local.admin_principals

  cluster_name  = aws_eks_cluster.this[0].name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

resource "aws_eks_identity_provider_config" "console" {
  count = local.console_oidc_enabled ? 1 : 0

  cluster_name = aws_eks_cluster.this[0].name

  oidc {
    identity_provider_config_name = "${var.config.name_prefix}-${var.config.environment}-console"
    issuer_url                    = var.config.headlamp.oidc.issuer_url
    client_id                     = var.config.headlamp.oidc.client_id
    username_claim                = try(var.config.headlamp.oidc.username_claim, "email")
    username_prefix               = try(var.config.headlamp.oidc.username_prefix, "oidc:")
    groups_claim                  = try(var.config.headlamp.oidc.groups_claim, "") != "" ? var.config.headlamp.oidc.groups_claim : null
    groups_prefix                 = try(var.config.headlamp.oidc.groups_claim, "") != "" ? try(var.config.headlamp.oidc.groups_prefix, "oidc:") : null
  }

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

data "aws_caller_identity" "current" {}
