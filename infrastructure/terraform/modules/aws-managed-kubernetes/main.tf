data "aws_availability_zones" "available" {
  region = local.placement.region
  state  = "available"
}

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "nodes_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_subnet" "control_plane" {
  region                  = local.placement.region
  vpc_id                  = var.network.vpc_id
  cidr_block              = local.cluster.aws_control_plane_subnet_cidr
  availability_zone       = [for zone in data.aws_availability_zones.available.names : zone if zone != local.placement.zone][0]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name                              = "${local.resource_prefix}-kubernetes-secondary-private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table_association" "control_plane" {
  region         = local.placement.region
  subnet_id      = aws_subnet.control_plane.id
  route_table_id = var.network.private_route_table_id
}

resource "aws_iam_role" "cluster" {
  name               = "${local.resource_prefix}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nodes" {
  name               = "${local.resource_prefix}-eks-nodes"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "this" {
  region   = local.placement.region
  name     = "${local.resource_prefix}-kubernetes"
  role_arn = aws_iam_role.cluster.arn
  version  = local.cluster.version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [
      var.network.private_subnet_id,
      aws_subnet.control_plane.id,
    ]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.config.bastion.allowed_cidrs
  }

  tags = local.tags

  # Keep the ingress EIP until EKS releases its NLB mapping during destroy.
  depends_on = [
    aws_eip.ingress,
    aws_iam_role_policy_attachment.cluster,
  ]
}

resource "aws_eks_node_group" "application" {
  region          = local.placement.region
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.resource_prefix}-application"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids = [
    var.network.private_subnet_id,
    aws_subnet.control_plane.id,
  ]
  instance_types = [var.config.machine_types[local.cluster.machine_type].aws]
  disk_size      = local.cluster.disk_size_gb
  version        = local.cluster.version

  scaling_config {
    desired_size = local.cluster.node_count
    min_size     = local.cluster.node_count
    max_size     = local.cluster.node_count
  }

  update_config {
    max_unavailable = 1
  }

  labels = { "oilscope.io/role" = "agent" }
  tags   = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.nodes,
    aws_route_table_association.control_plane,
  ]
}

resource "aws_eip" "ingress" {
  region = local.placement.region
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.resource_prefix}-kubernetes-ingress" })
}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.resource_prefix}-eks-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "load_balancer_controller" {
  name               = "${local.resource_prefix}-eks-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  tags               = local.tags
}

resource "aws_iam_policy" "load_balancer_controller" {
  name   = "${local.resource_prefix}-eks-load-balancer-controller"
  policy = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_eks_addon" "pod_identity_agent" {
  region                      = local.placement.region
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.application]
}

resource "aws_eks_addon" "metrics_server" {
  region                      = local.placement.region
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.application]
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  region          = local.placement.region
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

resource "aws_eks_addon" "ebs_csi" {
  region                      = local.placement.region
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  region          = local.placement.region
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer_controller.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.load_balancer_controller,
  ]
}

resource "aws_vpc_security_group_ingress_rule" "technitium_from_eks" {
  region                       = local.placement.region
  security_group_id            = var.bastion_security_group_id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  from_port                    = var.config.service_ports.technitium_admin
  to_port                      = var.config.service_ports.technitium_admin
  ip_protocol                  = "tcp"

  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-technitium-from-eks"
  })
}
