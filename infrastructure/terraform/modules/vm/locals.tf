locals {
  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
    automation_role = var.automation_role
    docker_version  = var.docker_version
  })
}
