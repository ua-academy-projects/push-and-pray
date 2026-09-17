locals {
  database_vm_entries = {
    for name, vm in local.config.vms : name => vm
    if vm.role == "database"
  }
  database_vm_name = try(one(keys(local.database_vm_entries)), null)
  database_vm      = try(local.database_vm_entries[local.database_vm_name], null)
  database_cloud   = try(lookup(local.database_vm, "cloud", local.config.default_cloud), null)
  database_internal_ip = try(
    lookup(local.database_vm.internal_ips, local.database_cloud, local.database_vm.internal_ip),
    null,
  )

  managed_database_enabled = var.database_mode == "managed"
  aws_managed_database     = local.managed_database_enabled && local.database_cloud == "aws"
  gcp_managed_database     = local.managed_database_enabled && local.database_cloud == "gcp"

  database_client_clouds = toset([
    for vm in values(local.config.vms) : lookup(vm, "cloud", local.config.default_cloud)
    if contains(["database", "history", "fetcher", "ui"], vm.role)
  ])

  database_host = (
    local.aws_managed_database ? module.aws_rds.address :
    local.gcp_managed_database ? module.gcp_cloud_sql.private_ip_address :
    local.database_internal_ip
  )
  database_secret_reference = (
    local.aws_managed_database ? module.aws_rds.master_user_secret_arn :
    local.gcp_managed_database ? module.gcp_cloud_sql.credentials_secret_id :
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
    sslmode          = local.managed_database_enabled ? "require" : "disable"
    secret_reference = local.database_secret_reference
    queue_backend    = local.managed_database_enabled ? "rabbitmq" : "pgmq"
    queue_host       = local.managed_database_enabled ? local.database_internal_ip : ""
    queue_port       = try(local.config.service_ports.rabbitmq, 5672)
    queue_username   = "oilscope"
    queue_vhost      = "oilscope"
    queue_secret_reference = (
      local.managed_database_enabled ? local.rabbitmq_secret_reference : ""
    )
  }
}

check "single_database_workload" {
  assert {
    condition     = length(local.database_vm_entries) == 1
    error_message = "Exactly one VM with role=database is required."
  }
}
