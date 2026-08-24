locals {
  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
    automation_role    = var.automation_role
    docker_version     = var.docker_version
    run_script         = file("${path.module}/templates/run.sh")
    compose_deployment = file("${path.module}/../../../docker/compose.deployment.yaml")
  })
}
