locals {
  resource_prefix = "${var.name_prefix}-${var.environment}"

  merged_common_labels = merge(
    {
      application = var.name_prefix
      environment = var.environment
      managed_by  = "terraform"
    },
    var.common_labels,
  )

  selected_vms = {
    for name, vm in var.vms : name => vm
    if coalesce(try(vm.cloud, null), var.default_cloud) == "gcp"
  }

  cloud_config = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
    registry_repository = var.registry_repository
    image_sha           = var.image_sha
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
