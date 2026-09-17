output "vms" {
  description = "Provider-neutral AWS VM records."
  value = {
    for name, vm in module.vm : name => {
      contract_version = 1
      logical_name     = name
      name             = vm.name
      role             = module.config.provisionable_vms[name].role
      provider         = module.config.cloud
      cloud            = module.config.cloud
      region           = module.config.location.region
      zone             = module.config.location.zone
      architecture     = try(module.config.provisionable_vms[name].architecture, "amd64")
      private_address  = vm.internal_ip
      public_address   = vm.public_ip
      internal_ip      = vm.internal_ip
      public_ip        = vm.public_ip
      network_tags     = vm.network_tags
      runtime_identity = vm.identity
      access_profiles  = toset([module.config.provisionable_vms[name].role])
      labels           = module.config.provisionable_vms[name].metadata
      disks = [{
        id      = vm.root_volume_id
        purpose = "boot"
      }]
      ssh = {
        user = keys(module.config.config.ssh_users)[0]
        port = try(module.config.provisionable_vms[name].ssh_port, 22)
        proxyjump_node = (
          module.config.provisionable_vms[name].role == "bastion" ? null : module.config.bastion_key
        )
        host_key_alias = "${module.config.resource_prefix}-${name}"
      }
    }
  }
}

output "configuration_valid" {
  description = "Whether every selected profile, cloud override, and AWS location resolves."
  value       = module.config.configuration_valid
}

output "secret_ids" {
  value = sort(module.config.all_secret_ids)
}

output "secret_resource_names" {
  value = {
    for secret_id in module.config.all_secret_ids :
    secret_id => "/${trimprefix(secret_id, "/")}"
  }
}

output "workload_secret_access" {
  value = {
    for name, workload in module.config.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}

output "managed_database" {
  value = module.config.managed_database_enabled ? merge(module.database[0].connection, {
    enabled = true
    cloud   = "aws"
  }) : null
}

output "network" {
  value = try({
    vpc_id              = module.network[0].vpc_id
    route_table_ids     = module.routing[0].route_table_ids
    database_subnet_ids = module.network[0].database_subnet_ids
    vpc_cidr            = module.config.network.vpc_cidr
  }, null)
}

output "managed_service_images" {
  value = try(module.config.manage_db ? {
    cloud    = "aws"
    registry = split("/", aws_ecr_repository.managed_service["redis"].repository_url)[0]
    redis    = "${aws_ecr_repository.managed_service["redis"].repository_url}:${module.config.config.managed_services.redis.target_tag}"
    rabbitmq = "${aws_ecr_repository.managed_service["rabbitmq"].repository_url}:${module.config.config.managed_services.rabbitmq.target_tag}"
  } : null, null)
}

output "application_images" {
  description = "Immutable cloud-registry references for first-party images."
  value = {
    for service, repository in aws_ecr_repository.application :
    service => "${repository.repository_url}:${module.config.config.registry.image_sha}"
  }
}

output "registry" {
  description = "Provider-neutral registry promotion and runtime contract."
  value = {
    provider       = "aws"
    immutable_tags = true
    scan_on_push   = true
    host = try(
      split("/", values(aws_ecr_repository.application)[0].repository_url)[0],
      null,
    )
    application = {
      for service, repository in aws_ecr_repository.application :
      service => "${repository.repository_url}:${module.config.config.registry.image_sha}"
    }
    managed = try(module.config.manage_db ? {
      redis    = "${aws_ecr_repository.managed_service["redis"].repository_url}:${module.config.config.managed_services.redis.target_tag}"
      rabbitmq = "${aws_ecr_repository.managed_service["rabbitmq"].repository_url}:${module.config.config.managed_services.rabbitmq.target_tag}"
    } : {}, {})
  }
}

output "monitoring" {
  description = "Provider-neutral monitoring resource identifiers."
  value = try(module.observability[0].contract, {
    dashboard_id     = null
    alert_policy_ids = []
    availability_id  = null
    log_metric_ids   = []
  })
}
