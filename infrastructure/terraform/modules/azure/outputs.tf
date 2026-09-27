output "names" {
  value = local.has_vms ? module.vm[0].names : {}
}

output "private_ips" {
  value = local.has_vms ? module.vm[0].private_ips : {}
}

output "public_ips" {
  value = local.has_vms ? module.vm[0].public_ips : {}
}

output "workload_names" {
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].names[name]
  } : {}
}

output "workload_roles" {
  value = {
    for name, vm in local.workload_vms : name => vm.role
  }
}

output "workload_private_ips" {
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].private_ips[name]
  } : {}
}

output "workload_public_ips" {
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].public_ips[name]
  } : {}
}

output "workload_secret_access" {
  value = local.secret_ids_by_vm
}

output "key_vault_id" {
  value = local.has_vms ? module.secrets[0].vault_id : null
}

output "key_vault_uri" {
  value = local.has_vms ? module.secrets[0].vault_uri : null
}

output "secret_resource_ids" {
  value = local.has_vms ? module.secrets[0].secret_resource_ids : {}
}

output "monitoring_summary" {
  value = local.monitoring_enabled ? module.monitoring[0].summary : null
}

output "database_connection" {
  value = local.database_mode == "managed" && local.managed_database_enabled ? {
    mode          = local.database_mode
    host          = module.database[0].host
    port          = module.database[0].port
    database_name = module.database[0].database_name
    username      = module.database[0].username
    sslmode       = "require"
    } : local.database_vm_name != null ? {
    mode          = local.database_mode
    host          = module.vm[0].private_ips[local.database_vm_name]
    port          = local.config.database.port
    database_name = local.config.database.name
    username      = local.config.database.user
    sslmode       = "disable"
  } : null
}

output "messaging_connection" {
  value = local.infrastructure_vm_name != null ? {
    provider     = local.database_mode == "managed" ? "rabbitmq" : "pgmq"
    host         = module.vm[0].private_ips[local.infrastructure_vm_name]
    port         = local.database_mode == "managed" ? local.config.service_ports.rabbitmq : local.config.database.port
    username     = local.database_mode == "managed" ? local.config.messaging.rabbitmq.username : local.config.database.user
    vhost        = local.database_mode == "managed" ? local.config.messaging.rabbitmq.vhost : null
    exchange     = local.database_mode == "managed" ? local.config.messaging.rabbitmq.exchange : null
    queue        = local.config.messaging.queue_name
    routing_key  = local.database_mode == "managed" ? local.config.messaging.rabbitmq.routing_key : null
    max_attempts = local.config.messaging.max_delivery_attempts
  } : null
}

output "session_connection" {
  value = local.infrastructure_vm_name != null ? {
    provider = local.database_mode == "managed" ? "redis" : "postgresql"
    host     = module.vm[0].private_ips[local.infrastructure_vm_name]
    port     = local.database_mode == "managed" ? local.config.service_ports.redis : local.config.database.port
  } : null
}
