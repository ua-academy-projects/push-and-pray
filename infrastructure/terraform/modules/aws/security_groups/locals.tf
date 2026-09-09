locals {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

    ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]

    selected_vms = {
        for name, vm in var.config.vms : name => vm
        if coalesce(try(vm.cloud, null), var.config.cloud) == "aws"
    }

    bastion = try(local.selected_vms.bastion, null)

    tag_present = {
        for tag in ["infra", "history", "fetcher", "ui"] :
        tag => anytrue([for vm in local.selected_vms : contains(vm.network_tags, tag)])
    }

    workload_tags_present = [
        for role in ["infra", "history", "fetcher", "ui"] : role
        if local.tag_present[role]
    ]
}
