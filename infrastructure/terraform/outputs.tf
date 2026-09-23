output "gcp_vms" {
  value = try(module.gcp_vm[0].vms, {})
}

output "aws_vms" {
  value = try(module.aws_vm[0].vms, {})
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
  )
}
