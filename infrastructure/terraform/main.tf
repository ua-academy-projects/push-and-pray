resource "terraform_data" "config_contract" {
  lifecycle {
    precondition {
      condition = (
        (local.manage_db && local.database_vm_count == 0) ||
        (!local.manage_db && local.database_vm_count == 1)
      )
      error_message = "manage_db=true requires no database VM; manage_db=false requires exactly one database VM."
    }

    precondition {
      condition     = !local.manage_db || (var.database_password != null && try(length(var.database_password) > 0, false))
      error_message = "database_password is required when manage_db=true."
    }

    precondition {
      condition     = !local.mixed_cloud || local.mixed_network_enabled
      error_message = "A configuration that uses AWS and GCP must enable mixed_network."
    }
  }
}

module "gcp" {
  source = "./modules/gcp"

  project_config_path          = var.project_config_path
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  secret_version_managers      = var.secret_version_managers
  database_password            = var.database_password

  depends_on = [terraform_data.config_contract]
}

module "aws" {
  source = "./modules/aws"

  project_config_path          = var.project_config_path
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  database_password            = var.database_password

  depends_on = [terraform_data.config_contract]
}
