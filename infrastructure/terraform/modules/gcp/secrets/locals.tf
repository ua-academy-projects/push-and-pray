locals {
  workload_secret_pairs = flatten([
    for vm_name, secret_ids in var.secret_ids_by_vm : [
      for secret_id in secret_ids : {
        vm_name               = vm_name
        secret_id             = secret_id
        service_account_email = var.workload_service_account_emails[vm_name]
      }
    ]
  ])

  secret_version_writers = {
    for pair in setproduct(sort(tolist(var.secret_ids)), var.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}
