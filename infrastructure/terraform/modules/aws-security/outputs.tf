output "security_group_ids" {
  description = "AWS security group IDs keyed by logical location and VM tag."
  value = {
    for location in keys(var.networks) : location => {
      for tag in toset(flatten([
        for vm in values(local.vms) : vm.tags if vm.location == location
      ])) : tag => aws_security_group.tag["${location}/${tag}"].id
    }
  }
}
