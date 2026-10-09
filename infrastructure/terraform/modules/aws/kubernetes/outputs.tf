output "cluster" {
  value = {
    cloud  = "aws"
    name   = aws_eks_cluster.main.name
    region = local.region
  }
  depends_on = [aws_eks_node_group.main, aws_eks_addon.ebs_csi]
}
