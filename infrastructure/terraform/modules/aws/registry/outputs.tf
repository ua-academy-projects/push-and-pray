output "repositories" {
  description = "Repository URL and the digest to deploy, by image. Helm values consume this; the digest comes from the project configuration, the URL from the registry."
  value = {
    for image, url in local.repository_urls : image => {
      url    = url
      digest = var.config.registry.image_digests[image]
      image  = "${url}@${var.config.registry.image_digests[image]}"
    }
  }
}

output "publisher_role_arn" {
  description = "Role GitHub Actions assumes to push images, or null when no github_repository is configured."
  value       = try(aws_iam_role.publisher[0].arn, null)
}
