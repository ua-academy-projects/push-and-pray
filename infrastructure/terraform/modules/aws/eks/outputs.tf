output "summary" {
  value = {
    cluster_name                   = aws_eks_cluster.this.name
    cluster_arn                    = aws_eks_cluster.this.arn
    endpoint                       = aws_eks_cluster.this.endpoint
    region                         = data.aws_region.current.region
    ecr_repository_url             = trimsuffix(aws_ecr_repository.application["fetcher"].repository_url, "/fetcher")
    oidc_provider_arn              = aws_iam_openid_connect_provider.this.arn
    certificate_arn                = aws_acm_certificate.ui.arn
    certificate_validation_options = aws_acm_certificate.ui.domain_validation_options
  }
}

data "aws_region" "current" {}
