locals {
    selected_vms = {
        for name, vm in var.config.vms : name => vm
        if coalesce(try(vm.cloud, null), var.config.cloud) == "aws"
    }

    public_vms = { for name, vm in local.selected_vms : name => vm if vm.assign_public_ip }
}
