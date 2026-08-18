locals {
  cloud_init_role_config = {
    infra   = <<-EOT
      ROLE=infra
      PROJECT_ID=${var.project_id}
      COMPOSE_FILE=/opt/oilscope/deployment/compose.infra.yaml
      GHCR_REQUIRED=false
      INFRA_DATA_DEVICE_NAME=${local.name_prefix}-data
      DB_PASSWORD_SECRET=${local.deployment_secrets.db_password.secret_id}
      RABBITMQ_USERNAME_SECRET=${local.deployment_secrets.rabbitmq_username.secret_id}
      RABBITMQ_PASSWORD_SECRET=${local.deployment_secrets.rabbitmq_password.secret_id}
    EOT
    history = <<-EOT
      ROLE=history
      PROJECT_ID=${var.project_id}
      COMPOSE_FILE=/opt/oilscope/deployment/compose.history.yaml
      GHCR_REQUIRED=true
      GHCR_OWNER=${var.ghcr_owner}
      IMAGE_TAG=${var.history_image_tag}
      DB_PASSWORD_SECRET=${local.deployment_secrets.db_password.secret_id}
      RABBITMQ_USERNAME_SECRET=${local.deployment_secrets.rabbitmq_username.secret_id}
      RABBITMQ_PASSWORD_SECRET=${local.deployment_secrets.rabbitmq_password.secret_id}
      GHCR_USERNAME_SECRET=${local.deployment_secrets.ghcr_username.secret_id}
      GHCR_READ_TOKEN_SECRET=${local.deployment_secrets.ghcr_read_token.secret_id}
    EOT
    fetcher = <<-EOT
      ROLE=fetcher
      PROJECT_ID=${var.project_id}
      COMPOSE_FILE=/opt/oilscope/deployment/compose.fetcher.yaml
      GHCR_REQUIRED=true
      GHCR_OWNER=${var.ghcr_owner}
      IMAGE_TAG=${var.fetcher_image_tag}
      DB_PASSWORD_SECRET=${local.deployment_secrets.db_password.secret_id}
      OILPRICEAPI_KEY_SECRET=${local.deployment_secrets.oilpriceapi_key.secret_id}
      GHCR_USERNAME_SECRET=${local.deployment_secrets.ghcr_username.secret_id}
      GHCR_READ_TOKEN_SECRET=${local.deployment_secrets.ghcr_read_token.secret_id}
    EOT
    ui      = <<-EOT
      ROLE=ui
      PROJECT_ID=${var.project_id}
      COMPOSE_FILE=/opt/oilscope/deployment/compose.ui.yaml
      GHCR_REQUIRED=true
      GHCR_OWNER=${var.ghcr_owner}
      IMAGE_TAG=${var.ui_image_tag}
      APP_DOMAIN=${var.app_domain}
      ACME_EMAIL=${var.acme_email}
      DB_PASSWORD_SECRET=${local.deployment_secrets.db_password.secret_id}
      GHCR_USERNAME_SECRET=${local.deployment_secrets.ghcr_username.secret_id}
      GHCR_READ_TOKEN_SECRET=${local.deployment_secrets.ghcr_read_token.secret_id}
    EOT
  }

  rendered_cloud_init = {
    for role in local.vm_roles : role => templatefile(
      "${path.module}/cloud-init/cloud-config.yaml.tftpl",
      {
        role                   = role
        role_config_b64        = base64encode(local.cloud_init_role_config[role])
        compose_b64            = filebase64("${path.module}/../docker/deployment/compose.${role}.yaml")
        bootstrap_script_b64   = filebase64("${path.module}/cloud-init/oilscope-bootstrap.sh")
        runtime_env_script_b64 = filebase64("${path.module}/cloud-init/oilscope-runtime-env.sh")
        deploy_script_b64      = filebase64("${path.module}/cloud-init/oilscope-deploy.sh")
        stop_script_b64        = filebase64("${path.module}/cloud-init/oilscope-stop.sh")
        systemd_unit_b64       = filebase64("${path.module}/cloud-init/oilscope-deployment.service")
      }
    )
  }
}
