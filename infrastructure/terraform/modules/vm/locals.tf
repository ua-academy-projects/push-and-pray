locals {
  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
    automation_role     = var.automation_role
    registry_repository = var.registry_repository
    image_sha           = var.image_sha
    docker_version      = var.docker_version
    run_script          = file("${path.module}/templates/run.sh")
    # Single source of truth for the deployment Compose file. It moved into the
    # compose_project role in #106; the name ends in .j2 by role convention, but
    # the file holds no Jinja - only the shell interpolation Compose expands.
    compose_deployment = file("${path.module}/../../../ansible/oilscope/platform/roles/compose_project/templates/compose.deployment.yaml.j2")
  })
}
