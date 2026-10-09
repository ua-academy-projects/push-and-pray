locals {
  database_vm_entries = {
    for name, vm in local.config.vms : name => vm
    if vm.role == "database"
  }
  database_vm_name = try(one(keys(local.database_vm_entries)), null)
  database_vm      = try(local.database_vm_entries[local.database_vm_name], null)
  database_cloud = coalesce(
    try(local.config.database.cloud, null),
    try(lookup(local.database_vm, "cloud", local.config.default_cloud), null),
    local.config.default_cloud,
  )
  database_internal_ip = try(
    lookup(local.database_vm.internal_ips, local.database_cloud, local.database_vm.internal_ip),
    null,
  )

  managed_database_enabled      = var.database_mode == "managed"
  kubernetes_database_enabled   = var.database_mode == "kubernetes"
  aws_managed_database          = local.managed_database_enabled && local.database_cloud == "aws"
  gcp_managed_database          = local.managed_database_enabled && local.database_cloud == "gcp"
  azure_managed_database        = local.managed_database_enabled && local.database_cloud == "azure"
  kubernetes_database_namespace = "oilscope"
  kubernetes_database_cluster   = "oilscope-postgres"
  kubernetes_database_host      = "${local.kubernetes_database_cluster}-rw.${local.kubernetes_database_namespace}.svc.cluster.local"
  kubernetes_queue_host         = "rabbitmq.${local.kubernetes_database_namespace}.svc.cluster.local"

  database_client_clouds = toset([
    for vm in values(local.config.vms) : lookup(vm, "cloud", local.config.default_cloud)
    if vm.role != "bastion"
  ])

  database_host = (
    local.kubernetes_database_enabled ? local.kubernetes_database_host :
    local.aws_managed_database ? module.aws_rds.address :
    local.gcp_managed_database ? module.gcp_cloud_sql.private_ip_address :
    local.azure_managed_database ? module.azure_postgresql.fqdn :
    local.database_internal_ip
  )
  database_secret_reference = (
    local.aws_managed_database ? module.aws_rds.master_user_secret_arn :
    local.gcp_managed_database ? module.gcp_cloud_sql.credentials_secret_id :
    local.azure_managed_database ? module.azure_postgresql.credentials_secret_id :
    try(local.database_vm.secret_mappings.POSTGRES_PASSWORD, "")
  )
  rabbitmq_secret_reference = try(local.database_vm.secret_mappings.RABBITMQ_PASSWORD, "rabbitmq-password")

  database_runtime = {
    mode             = var.database_mode
    cloud            = local.database_cloud
    host             = local.database_host
    port             = local.config.service_ports.postgresql
    name             = var.database_name
    username         = var.database_username
    sslmode          = local.managed_database_enabled || local.kubernetes_database_enabled ? "require" : "disable"
    secret_reference = local.database_secret_reference
    queue_backend    = var.database_mode == "self_hosted" ? "pgmq" : "rabbitmq"
    queue_host = (
      local.kubernetes_database_enabled ? local.kubernetes_queue_host :
      local.database_internal_ip == null ? "" : local.database_internal_ip
    )
    queue_port     = try(local.config.service_ports.rabbitmq, 5672)
    queue_username = "oilscope"
    queue_vhost    = "oilscope"
    queue_secret_reference = (
      var.database_mode == "self_hosted" ? "" : local.rabbitmq_secret_reference
    )
  }
}

check "database_workload_matches_mode" {
  assert {
    condition = (
      var.database_mode == "self_hosted" ?
      length(local.database_vm_entries) == 1 :
      var.database_mode == "managed" ?
      length(local.database_vm_entries) <= 1 :
      length(local.database_vm_entries) == 0
    )
    error_message = "self_hosted requires one database VM; managed allows at most one; kubernetes requires none."
  }
}

check "kubernetes_database_region_exists" {
  assert {
    condition = (
      !local.kubernetes_database_enabled ||
      can(
        local.config.clouds[local.database_cloud].regions[
          local.config.database.kubernetes_region
        ]
      )
    )
    error_message = "kubernetes mode requires database.kubernetes_region to exist in the selected cloud region map."
  }
}
