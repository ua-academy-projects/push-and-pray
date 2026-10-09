output "cluster" {
  description = "EKS cluster connection metadata."
  value = {
    name     = aws_eks_cluster.this.name
    location = local.placement.region
    endpoint = aws_eks_cluster.this.endpoint
  }
}

output "ingress" {
  description = "Reserved address for a managed ingress load balancer."
  value = {
    address       = aws_eip.ingress.public_ip
    allocation_id = aws_eip.ingress.id
  }
}

output "network" {
  description = "AWS network identifiers used by the EKS ingress controllers."
  value = {
    vpc_id            = var.network.vpc_id
    public_subnet_id  = var.network.public_subnet_id
    private_subnet_id = var.network.private_subnet_id
  }
}
