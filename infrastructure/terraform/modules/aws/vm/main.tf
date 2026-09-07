data "aws_ami" "selected" {

    for_each = toset([
        for vm in local.selected_vms :
        coalesce(try(vm.image, null), var.config.image)
    ])
    most_recent = true

    filter {
        name = "name"
        values = [var.config.images[each.key]["aws"]]
    }

    owners = ["099720109477"]
}

resource "aws_instance" "workload" {
    for_each = local.selected_vms
    ami = data.aws_ami.selected[coalesce(try(each.value.image, null), var.config.image)].id 
    instance_type = var.config.machine_types[each.value.machine_type]["aws"]
    subnet_id = each.value.assign_public_ip ? var.management_subnet_id : var.workload_subnet_id
    private_ip = each.value.internal_ip
    vpc_security_group_ids = [for tag in each.value.network_tags : var.security_group_ids[tag]]
    iam_instance_profile = var.instance_profile_names[each.key]
    root_block_device {
        volume_size = each.value.boot_disk.size_gb
        volume_type = var.config.disk_types[each.value.boot_disk.type]["aws"]
    }
    tags = merge(
        { Name = "${local.resource_prefix}-${each.key}", Role = each.value.role },
        try(each.value.labels, {})
    )
}

resource "aws_eip_association" "public" {
    for_each = var.allocation_ids
    instance_id = aws_instance.workload[each.key].id
    allocation_id = each.value
}