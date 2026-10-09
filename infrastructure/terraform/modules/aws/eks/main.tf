resource "aws_eks_cluster" "main" {
  count = var.enabled ? 1 : 0

  name     = local.cluster_name
  role_arn = aws_iam_role.cluster[0].arn

  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = local.public_access_cidrs
  }

  tags = {
    Name = local.cluster_name
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_node_group" "main" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${local.resource_prefix}-nodes"
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = var.subnet_ids
  instance_types  = [local.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = local.node_count
    min_size     = local.node_count
    max_size     = local.node_count
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${local.resource_prefix}-nodes"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.pre_node,
  ]
}
