locals {
  config = jsondecode(file(var.project_config_path))
}
