locals {
  enabled            = var.config.default_cloud == "aws"
  managed_kubernetes = try(var.config.managed_kubernetes, false)
  create             = local.enabled && try(var.config.registry.create, true)
  images             = local.enabled ? keys(var.config.registry.image_digests) : []
  publisher          = try(var.config.registry.github_repository, null)

  repositories = local.create ? aws_ecr_repository.this : data.aws_ecr_repository.existing

  repository_arns = { for image, repository in local.repositories : image => repository.arn }
  repository_urls = { for image, repository in local.repositories : image => repository.repository_url }
}
