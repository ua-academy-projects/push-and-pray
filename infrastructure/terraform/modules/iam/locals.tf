locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  aws_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }
  gcp_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }
  aws_tags = merge(var.config.common_labels, {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = "aws"
  })
}
