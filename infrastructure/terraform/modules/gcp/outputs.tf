output "vms" {
  description = "Provider-neutral GCP VM records."
  value = {
    for name, vm in module.vm : name => {
      name             = vm.name
      role             = module.config.provisionable_vms[name].role
      cloud            = module.config.cloud
      internal_ip      = vm.internal_ip
      public_ip        = vm.public_ip
      network_tags     = vm.network_tags
      runtime_identity = vm.service_account_email
    }
  }
}

output "configuration_valid" {
  description = "Whether every selected profile, cloud override, and GCP location resolves."
  value       = module.config.configuration_valid
}

output "secret_ids" {
  value = sort(module.config.all_secret_ids)
}

output "secret_resource_names" {
  value = {
    for secret_id, secret in google_secret_manager_secret.this :
    secret_id => secret.name
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
    cloud   = "gcp"
  }) : null
}

output "network" {
  value = try({
    network_id = module.network[0].network_id
    vpc_cidr   = module.config.network.vpc_cidr
    region     = module.config.location.region
  }, null)
}

output "managed_service_images" {
  value = try(module.config.manage_db ? {
    cloud    = "gcp"
    registry = "${module.config.location.region}-docker.pkg.dev"
    redis    = "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.managed_services[0].repository_id}/redis:${module.config.config.managed_services.redis.target_tag}"
    rabbitmq = "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.managed_services[0].repository_id}/rabbitmq:${module.config.config.managed_services.rabbitmq.target_tag}"
  } : null, null)
}
