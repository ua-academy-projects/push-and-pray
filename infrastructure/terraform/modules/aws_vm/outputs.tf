output "vms" {
  description = "Created AWS VMs keyed by configuration name."

  value = {
    for name, vm in aws_instance.vms : name => {
      name             = vm.tags["Name"]
      instance_id      = vm.id
      cloud            = "aws"
      role             = local.vms[name].role
      internal_ip      = vm.private_ip
      public_ip        = local.vms[name].assign_public_ip ? aws_eip.public[name].public_ip : null
      tags             = vm.tags
      instance_profile = vm.iam_instance_profile
      secret_access    = sort(distinct(values(local.vms[name].secret_mappings)))
    }
  }
}
