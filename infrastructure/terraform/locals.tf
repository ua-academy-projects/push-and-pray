locals {
  config = jsondecode(file(var.project_config_path))

  all_workload_roles = merge(
     module.gcp.workload_roles,
     module.aws.workload_roles,
  )
  all_public_ips = merge(
    module.gcp.public_ips,
    module.aws.public_ips,
  )

  ui_vm_name = one([
    for vm_name, role in local.all_workload_roles :
    vm_name
    if role == "ui"
  ])

  ui_public_ip = local.all_public_ips[local.ui_vm_name]
}
