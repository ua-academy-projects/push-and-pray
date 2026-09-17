locals {
  config = jsondecode(file(var.project_config_path))
  schema_version = try(
    tonumber(local.config.schema_version),
    0,
  )
  cloud_provider = lower(try(
    local.config.cloud_provider,
    local.config.default_cloud,
  ))
  data_profile = lower(try(
    local.config.data_profile,
    try(local.config.manage_db, false) ? "managed" : "portable",
  ))
  runtime = lower(try(local.config.deployment_runtime, "compose"))

  bastion = try([
    for name, node in var.nodes : merge(node, { logical_name = name })
    if node.role == "bastion"
  ][0], null)
  ui = try(var.nodes.ui, null)
  database_node = try([
    for name, node in var.nodes : merge(node, { logical_name = name })
    if node.role == "database"
  ][0], null)

  application_images = {
    fetcher  = "${local.config.registry.repository}/fetcher:${local.config.registry.image_sha}"
    history  = "${local.config.registry.repository}/history:${local.config.registry.image_sha}"
    ui       = "${local.config.registry.repository}/ui:${local.config.registry.image_sha}"
    database = "${local.config.registry.repository}/database:${local.config.registry.image_sha}"
  }
  managed_images = var.managed_service_images == null ? {} : {
    redis    = var.managed_service_images.redis
    rabbitmq = var.managed_service_images.rabbitmq
  }

  database = local.data_profile == "managed" ? {
    mode      = "managed"
    engine    = "postgresql"
    host      = try(var.managed_database.host, null)
    port      = try(var.managed_database.port, local.config.service_ports.postgresql)
    name      = try(var.managed_database.name, local.config.database.database_name)
    username  = try(var.managed_database.user, local.config.database.username)
    secret_id = local.config.database.password_secret_id
    } : {
    mode      = "portable"
    engine    = "postgresql"
    host      = try(local.database_node.private_address, null)
    port      = local.config.service_ports.postgresql
    name      = "oil_tracker"
    username  = "oil_tracker"
    secret_id = try(local.config.secrets_by_role.database.POSTGRES_PASSWORD, null)
  }

  deployment = {
    contract_version = 1
    schema_version   = local.schema_version
    deployment_name  = local.config.name_prefix
    environment      = local.config.environment
    provider         = var.provider_name
    data_profile     = local.data_profile
    runtime          = local.runtime
    nodes            = var.nodes
    bastion          = local.bastion
    ui = {
      hostname       = local.config.vms.ui.public_endpoint.hostname
      public_address = try(local.ui.public_address, null)
      url            = "https://${local.config.vms.ui.public_endpoint.hostname}"
    }
    database = local.database
    registry = {
      repositories = {
        application      = local.config.registry.repository
        managed_services = try(var.managed_service_images.registry, null)
      }
      images = merge(local.application_images, local.managed_images)
    }
    monitoring = var.monitoring
  }
}
