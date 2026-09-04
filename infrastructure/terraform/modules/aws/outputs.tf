output "vms" {
  value = {
    for name, vm in local.vms : name => {
      name          = module.vm[name].name
      instance_id   = module.vm[name].instance_id
      cloud         = local.cloud
      role          = vm.role
      internal_ip   = module.vm[name].internal_ip
      public_ip     = module.vm[name].public_ip
      tags          = vm.tags
      secret_access = sort(distinct(values(vm.secret_mappings)))
      iam_role_arn = aws_iam_role.vm[name].arn
    }
  }
}