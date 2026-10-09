resource "aws_eks_node_group" "this" {
  count = local.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "${var.config.name_prefix}-${var.config.environment}-nodes"
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = [var.network.workload_subnet_id]
  version         = var.config.kubernetes.eks.version

  ami_type       = try(var.config.kubernetes.eks.node_group.ami_type, "AL2023_x86_64_STANDARD")
  capacity_type  = try(var.config.kubernetes.eks.node_group.capacity_type, "ON_DEMAND")
  instance_types = [var.config.size_map[var.config.kubernetes.eks.node_group.size].aws]
  disk_size      = var.config.kubernetes.eks.node_group.disk_size_gb

  scaling_config {
    desired_size = var.config.kubernetes.eks.node_group.desired_size
    min_size     = var.config.kubernetes.eks.node_group.min_size
    max_size     = var.config.kubernetes.eks.node_group.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}
