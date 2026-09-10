locals {
  resource_prefix     = "${var.config.name_prefix}-${var.config.environment}"
  ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  bastion = try(local.selected_vms.bastion, null)

  # Terraform owns network reachability; Ansible owns the sshd policy inside
  # the VM. A fresh instance still listens on 22, so both ports stay reachable
  # from the operator CIDRs: 22 is how Ansible gets in the first time, the
  # final port is what it moves sshd to. Nothing listens on 22 afterwards.
  bastion_ssh_ports = local.bastion == null ? [] : distinct([
    tostring(local.bastion.ssh_port),
    "22",
  ])

  tag_present = {
    for tag in ["infra", "history", "fetcher", "ui"] :
    tag => anytrue([for vm in local.selected_vms : contains(vm.network_tags, tag)])
  }

  workload_target_tags = [
    for role in ["infra", "history", "fetcher", "ui"] : var.network_tags[role]
    if local.tag_present[role]
  ]
}
