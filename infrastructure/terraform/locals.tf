locals {
  config = jsondecode(file(var.project_config_path))

  kubernetes_enabled = lookup(lookup(local.config, "kubernetes", {}), "enabled", false) && lookup(lookup(local.config, "kubernetes", {}), "mode", "k3s") == "k3s"
  eks_enabled        = lookup(lookup(local.config, "kubernetes", {}), "enabled", false) && lookup(lookup(local.config, "kubernetes", {}), "mode", "k3s") == "eks"
  gke_enabled        = lookup(lookup(local.config, "kubernetes", {}), "enabled", false) && lookup(lookup(local.config, "kubernetes", {}), "mode", "k3s") == "gke"

  all_workload_roles = merge(
    module.gcp.workload_roles,
    module.aws.workload_roles,
    module.azure.workload_roles,
  )
  all_public_ips = merge(
    module.gcp.public_ips,
    module.aws.public_ips,
    module.azure.public_ips,
  )

  ui_vm_name = one([
    for vm_name, role in local.all_workload_roles :
    vm_name
    if role == "ui"
  ])

  ui_public_ip = local.kubernetes_enabled ? module.gcp.kubernetes.ingress_public_ip : local.gke_enabled ? module.gcp.gke.ingress_ip : local.eks_enabled ? null : local.all_public_ips[local.ui_vm_name]
  public_endpoint_vm_name = local.kubernetes_enabled ? one([
    for name, vm in local.config.vms : name
    if vm.role == "k3s_server" && vm.assign_public_ip
  ]) : local.eks_enabled || local.gke_enabled ? null : local.ui_vm_name
}
