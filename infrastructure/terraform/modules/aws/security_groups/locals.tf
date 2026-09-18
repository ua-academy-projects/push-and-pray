locals {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

    ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]

    selected_vms = var.selected_vms

    bastion = try(local.selected_vms.bastion, null)

    bastion_ssh_rules = local.bastion == null ? {} : {
        for pair in setproduct(
            local.bastion.allowed_cidrs,
            distinct([local.bastion.ssh_port, 22])
        ) : "${pair[0]}-${pair[1]}" => {
            cidr = pair[0]
            port = pair[1]
        }
    }

    tag_present = {
        for tag in ["infra", "history", "fetcher", "ui"] :
        tag => anytrue([for vm in local.selected_vms : contains(vm.network_tags, tag)])
    }

    workload_tags_present = [
        for role in ["infra", "history", "fetcher", "ui"] : role
        if local.tag_present[role]
    ]
}
