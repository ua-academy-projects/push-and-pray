locals {
    selected_vms = var.selected_vms

    public_vms = { for name, vm in local.selected_vms : name => vm if vm.assign_public_ip }
}
