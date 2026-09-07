locals {
  gcp_workload_vms = {
    for name, vm in var.config.vms : name => vm
    if vm.role != "bastion" && coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  all_secret_ids = distinct(flatten([
    for workload in values(local.gcp_workload_vms) : values(workload.secret_mappings)
  ]))

  workload_secret_pairs = flatten([
    for name, workload in local.gcp_workload_vms : [
      for secret_id in distinct(values(workload.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  secret_version_writers = {
    for pair in setproduct(sort(local.all_secret_ids), var.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}
