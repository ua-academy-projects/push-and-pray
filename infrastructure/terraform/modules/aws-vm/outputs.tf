output "vms" {
  description = "AWS VM information keyed by configuration name."

  value = {
    for name, vm in aws_instance.this : name => {
      name                  = vm.tags["Name"]
      instance_id           = vm.id
      internal_ip           = vm.private_ip
      public_ip             = vm.public_ip
      network_tags          = local.vms[name].network_tags
      service_account_email = null
      cloud                 = local.cloud_name
      role                  = local.vms[name].role
    }
  }
}
