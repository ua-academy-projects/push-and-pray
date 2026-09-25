output "gcp_vms" {
  value = try(module.gcp_vm[0].vms, {})
}

output "aws_vms" {
  value = try(module.aws_vm[0].vms, {})
}

output "azure_vms" {
  value = try(module.azure_vm[0].vms, {})
}

output "service_endpoints" {
  description = "Non-secret service connection data consumed by Ansible."
  value = merge(
    contains(local.enabled_clouds, "aws") ? {
      aws = {
        database = module.aws_database[0].connection
        rabbitmq = {
          host            = module.aws_vm[0].vms["infra"].internal_ip
          port            = local.config.services.rabbitmq.amqp_port
          management_port = local.config.services.rabbitmq.management_port
          username        = local.config.services.rabbitmq.username
          vhost           = local.config.services.rabbitmq.vhost
          queue           = local.config.services.rabbitmq.queue
        }
        redis = {
          host     = module.aws_vm[0].vms["infra"].internal_ip
          port     = local.config.services.redis.port
          database = local.config.services.redis.database
        }
      }
    } : {},
    contains(local.enabled_clouds, "gcp") ? {
      gcp = {
        database = module.gcp_database[0].connection
        rabbitmq = {
          host            = module.gcp_vm[0].vms["infra"].internal_ip
          port            = local.config.services.rabbitmq.amqp_port
          management_port = local.config.services.rabbitmq.management_port
          username        = local.config.services.rabbitmq.username
          vhost           = local.config.services.rabbitmq.vhost
          queue           = local.config.services.rabbitmq.queue
        }
        redis = {
          host     = module.gcp_vm[0].vms["infra"].internal_ip
          port     = local.config.services.redis.port
          database = local.config.services.redis.database
        }
      }
    } : {},
    contains(local.enabled_clouds, "azure") ? {
      azure = {
        database = module.azure_database[0].connection
        rabbitmq = {
          host            = try(module.azure_vm[0].vms["infra"].internal_ip, null)
          port            = local.config.services.rabbitmq.amqp_port
          management_port = local.config.services.rabbitmq.management_port
          username        = local.config.services.rabbitmq.username
          vhost           = local.config.services.rabbitmq.vhost
          queue           = local.config.services.rabbitmq.queue
        }
        redis = {
          host     = try(module.azure_vm[0].vms["infra"].internal_ip, null)
          port     = local.config.services.redis.port
          database = local.config.services.redis.database
        }
        secret_store = {
          vault_uri = module.azure_basic[0].key_vault_uri
        }
      }
    } : {},
  )
}

output "monitoring" {
  description = "Provider destinations for host metrics and centralized logs."
  value = merge(
    try({ aws = module.aws_monitoring[0].destination }, {}),
    try({ gcp = module.gcp_monitoring[0].destination }, {}),
    try({ azure = module.azure_monitoring[0].destination }, {}),
  )
}
