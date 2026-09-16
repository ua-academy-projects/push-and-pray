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
  description = "AWS workload VM names, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].names[name]
  } : {}
}

output "workload_roles" {
  description = "AWS workload roles, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => vm.role
  }
}

output "workload_private_ips" {
  description = "AWS workload private IPs, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].private_ips[name]
  } : {}
}

output "workload_public_ips" {
  description = "AWS workload public IPs, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].public_ips[name]
  } : {}
}

output "workload_secret_access" {
  description = "Secret IDs each AWS workload instance role may read."
  value       = local.secret_ids_by_vm
}

output "secret_arns" {
  value = module.secrets.secret_arns
}

output "monitoring_summary" {
  description = "AWS CloudWatch and SNS resources created for monitoring."
  value       = local.monitoring_enabled ? module.monitoring[0].summary : null
}

output "database_connection" {
  description = "Database connection values resolved from self-managed PostgreSQL or private managed RDS."
  value = local.database_vm_name == null ? null : local.database_mode == "managed" ? {
    mode          = local.database_mode
    host          = module.database[0].host
    port          = module.database[0].port
    database_name = module.database[0].database_name
    username      = module.database[0].username
    sslmode       = "require"
    } : {
    mode          = local.database_mode
    host          = module.vm[0].private_ips[local.database_vm_name]
    port          = local.config.database.port
    database_name = local.config.database.name
    username      = local.config.database.user
    sslmode       = "disable"
  }
}

output "messaging_connection" {
  description = "Non-secret messaging connection selected by database mode."
  value = local.database_vm_name != null ? {
    provider     = local.database_mode == "managed" ? "rabbitmq" : "pgmq"
    host         = module.vm[0].private_ips[local.database_vm_name]
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
  description = "Non-secret UI session-store connection selected by database mode."
  value = local.database_vm_name != null ? {
    provider = local.database_mode == "managed" ? "redis" : "postgresql"
    host     = module.vm[0].private_ips[local.database_vm_name]
    port     = local.database_mode == "managed" ? local.config.service_ports.redis : local.config.database.port
  } : null
}
