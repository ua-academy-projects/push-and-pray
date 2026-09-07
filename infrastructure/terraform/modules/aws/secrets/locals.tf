locals {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

    aws_workload_vms = {
        for name, vm in var.config.vms : name => vm
        if vm.role != "bastion" && coalesce(try(vm.cloud, null), var.config.cloud) == "aws"
    }

    all_aws_secret_ids = distinct(flatten([
        for workload in values(local.aws_workload_vms) : values(workload.secret_mappings)
    ]))
}
