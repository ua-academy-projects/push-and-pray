variable "config" {
  type = any
}

locals {
  region = var.config.locations[var.config.default_location].aws.region
}

resource "aws_ecr_repository" "app" {
  for_each = toset(["history", "fetcher", "ui", "database-cnpg"])

  region = local.region
  name   = "${var.config.name_prefix}-${var.config.environment}-${each.key}"
  tags   = merge(var.config.common_labels, { environment = var.config.environment })
}

output "registry" {
  value = {
    cloud  = "aws"
    name   = "${var.config.name_prefix}-${var.config.environment}"
    region = local.region
    server = split("/", aws_ecr_repository.app["history"].repository_url)[0]
    images = { for image, repository in aws_ecr_repository.app : image => repository.repository_url }
  }
}
