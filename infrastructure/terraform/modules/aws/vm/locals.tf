locals {
  subnet_id         = contains(["bastion", "ui"], var.role) ? var.management_subnet_id : var.workload_subnet_id
  security_group_id = var.security_group_ids[var.role]

  cloud_init_user_data = templatefile("${path.module}/../templates/ssh-users.yaml.tfpl", {
    ssh_users = var.ssh_users
  })
}
