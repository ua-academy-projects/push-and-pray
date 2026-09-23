locals {
  config = jsondecode(file(var.project_config_path))

  managed_db_private_ip = try(coalesce(
    try(module.gcp_vm.managed_db_private_ip, null),
    try(module.aws_vm.managed_db_private_ip, null),
    try(module.azure_vm.managed_db_private_ip, null),
  ), "")
}
