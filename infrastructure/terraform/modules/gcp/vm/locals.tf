locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  merged_common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
    registry_repository = var.config.registry.repository
    image_sha           = var.config.registry.image_sha
    docker_version      = var.docker_version
    run_script          = file("${path.module}/templates/run.sh")
    # Single source of truth for the deployment Compose file. It moved into the
    # compose_project role in #106; the name ends in .j2 by role convention, but
    # the file holds no Jinja - only the shell interpolation Compose expands.
    compose_deployment = file("${path.module}/../../../../ansible/oilscope/platform/roles/compose_project/templates/compose.deployment.yaml.j2")
  })

  bastion_startup_scripts = {
    for name, vm in local.selected_vms : name => templatefile("${path.module}/templates/bastion-startup.sh.tftpl", {
      ssh_port = vm.ssh_port
    })
    if vm.role == "bastion"
  }
}
