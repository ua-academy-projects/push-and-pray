locals {
    resource_prefix = "${var.name_prefix}-${var.environment}"

    selected_vms = {
        for name, vm in var.vms : name => vm
        if coalesce(try(vm.cloud, null), var.default_cloud) == "aws"
    }
}