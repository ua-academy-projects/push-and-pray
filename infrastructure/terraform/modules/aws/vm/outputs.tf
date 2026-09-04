output "vms" {
  description = "Created AWS VMs keyed by logical VM name."
  value = {
    for name, vm in aws_instance.workload : name => {
      name                  = "${local.resource_prefix}-${name}"
      role                  = local.vms[name].role
      internal_ip           = vm.private_ip
      public_ip             = try(aws_eip.public[name].public_ip, null)
      network_tags          = []
      identity_id           = aws_iam_role.workload[name].arn
      service_account_email = null
    }
  }
}
