locals {
  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
    automation_role     = var.automation_role
    registry_repository = var.registry_repository
    image_sha           = var.image_sha
    docker_version      = var.docker_version
    run_script          = file("${path.module}/templates/run.sh")
    compose_deployment  = file("${path.module}/../../..//ansible/oilscope/platform/roles/compose_project/templates/compose.deployment.yaml.j2")
  })
}
