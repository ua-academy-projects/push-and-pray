locals {
  service_account_roles = {
    for grant in flatten([
      for vm_name, email in var.service_account_emails : [
        for role in var.writer_roles : {
          key   = "${vm_name}/${role}"
          email = email
          role  = role
        }
      ]
    ]) : grant.key => grant
  }
}
