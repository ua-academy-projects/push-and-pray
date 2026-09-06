locals {
  user_data = "#cloud-config\n${yamlencode({
    users = [
      for username, public_key in var.ssh_users : {
        name                = username
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        ssh_authorized_keys = [trimspace(public_key)]
      }
    ]
  })}"
}
