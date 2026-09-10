locals {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

    selected_vms = {
        for name, vm in var.config.vms : name => vm
        if coalesce(try(vm.cloud, null), var.config.cloud) == "aws"
    } 
    merged_common_tags = merge(
        {
            Application = var.config.name_prefix
            Environment = var.config.environment
            ManagedBy   = "terraform"
        },
        var.config.common_labels,
    )

    instance_user_data = {
        for name, vm in local.selected_vms : name => templatefile("${path.module}/templates/user-data.yaml.tftpl", {
            ssh_users = var.config.ssh_users
        })
    }
}
