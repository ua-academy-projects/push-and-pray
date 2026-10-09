resource "aws_iam_role" "ebs_csi" {
  count = local.enabled ? 1 : 0

  name               = "${var.config.name_prefix}-${var.config.environment}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = local.enabled ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count = local.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi[0].arn

  depends_on = [aws_eks_addon.pod_identity]
}

resource "aws_iam_role" "load_balancer" {
  count = local.enabled ? 1 : 0

  name               = "${var.config.name_prefix}-${var.config.environment}-load-balancer"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_iam_role_policy" "load_balancer" {
  count = local.enabled ? 1 : 0

  name   = "${var.config.name_prefix}-${var.config.environment}-load-balancer"
  role   = aws_iam_role.load_balancer[0].id
  policy = file("${path.module}/policies/load-balancer-controller.json")
}

resource "aws_eks_pod_identity_association" "load_balancer" {
  count = local.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer[0].arn

  depends_on = [aws_eks_addon.pod_identity]
}

resource "aws_iam_role" "cluster_metrics" {
  count = local.enabled ? 1 : 0

  name               = "${var.config.name_prefix}-${var.config.environment}-cluster-metrics"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_iam_role_policy" "cluster_metrics" {
  count = local.enabled ? 1 : 0

  name = "${var.config.name_prefix}-${var.config.environment}-cluster-metrics"
  role = aws_iam_role.cluster_metrics[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = [
          "${var.config.name_prefix}-${var.config.environment}/Cluster",
        ] } }
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "cluster_metrics" {
  count = local.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  namespace       = var.config.kubernetes.namespace
  service_account = "${var.config.name_prefix}-cluster-metrics"
  role_arn        = aws_iam_role.cluster_metrics[0].arn

  depends_on = [aws_eks_addon.pod_identity]
}

resource "aws_iam_role" "registry_refresh" {
  count = local.enabled ? 1 : 0

  name               = "${var.config.name_prefix}-${var.config.environment}-registry-refresh"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}

resource "aws_eks_pod_identity_association" "registry_refresh" {
  count = local.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  namespace       = var.config.kubernetes.namespace
  service_account = "${var.config.name_prefix}-registry-refresh"
  role_arn        = aws_iam_role.registry_refresh[0].arn

  depends_on = [aws_eks_addon.pod_identity]
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}
