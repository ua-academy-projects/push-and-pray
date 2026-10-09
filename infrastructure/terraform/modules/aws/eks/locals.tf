locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  cluster_name = "${local.resource_prefix}-eks"

  region = var.config.regions[var.config.region].aws.region

  node_count = try(var.config.kubernetes.node_count, 1)

  node_instance_type = try(var.config.machine_types[var.config.kubernetes.node_machine_type].aws, null)

  public_access_cidrs = try(var.config.vms.bastion.allowed_cidrs, [])

  bastion_ports = var.enabled && try(var.config.vms.bastion, null) != null ? toset(["80", "443"]) : toset([])

  pre_node_addons = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])

  post_node_addons = toset(["coredns", "metrics-server"])
}
