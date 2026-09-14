locals {
  managed_secret_mappings = local.database_mode == "managed" ? {
    database = {
      DATABASE_HOST     = local.managed_database_host_secret_id
      RABBITMQ_PASSWORD = local.rabbitmq_password_secret_id
    }
    history = {
      DATABASE_HOST     = local.managed_database_host_secret_id
      RABBITMQ_PASSWORD = local.rabbitmq_password_secret_id
    }
    fetcher = {
      RABBITMQ_PASSWORD = local.rabbitmq_password_secret_id
    }
    ui = {}
  } : {}

  effective_secret_mappings = {
    for role, mappings in local.config.application.secret_mappings :
    role => merge(
      {
        for environment_name, secret_id in mappings :
        environment_name => secret_id
        if !(local.database_mode == "managed" && role == "fetcher" && environment_name == "POSTGRES_PASSWORD")
      },
      try(local.managed_secret_mappings[role], {}),
    )
  }

  gcp_workload_vms = {
    for name, workload in local.workload_vms :
    name => workload
    if workload.cloud == "gcp"
  }

  aws_workload_vms = {
    for name, workload in local.workload_vms :
    name => workload
    if workload.cloud == "aws"
  }

  gcp_secret_ids = distinct(flatten([
    for workload in values(local.gcp_workload_vms) :
    values(local.effective_secret_mappings[workload.role])
  ]))

  aws_secret_ids = distinct(flatten([
    for workload in values(local.aws_workload_vms) :
    values(local.effective_secret_mappings[workload.role])
  ]))

  gcp_workload_secret_pairs = flatten([
    for name, workload in local.gcp_workload_vms : [
      for secret_id in distinct(values(local.effective_secret_mappings[workload.role])) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  gcp_secret_version_writers = {
    for pair in setproduct(
      sort(local.gcp_secret_ids),
      var.secret_version_managers,
    ) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}

resource "google_secret_manager_secret_version" "managed_database_password" {
  count = local.database_mode == "managed" && local.managed_cloud == "gcp" ? 1 : 0

  secret      = google_secret_manager_secret.this[local.managed_database_password_secret_ids[0]].id
  secret_data = random_password.managed_database[0].result
}

resource "google_secret_manager_secret_version" "managed_database_host" {
  count = local.database_mode == "managed" && local.managed_cloud == "gcp" ? 1 : 0

  secret      = google_secret_manager_secret.this[local.managed_database_host_secret_id].id
  secret_data = module.gcp_managed_database[0].host
}

resource "google_secret_manager_secret_version" "rabbitmq_password" {
  count = local.database_mode == "managed" && local.managed_cloud == "gcp" ? 1 : 0

  secret      = google_secret_manager_secret.this[local.rabbitmq_password_secret_id].id
  secret_data = random_password.rabbitmq[0].result
}

resource "google_secret_manager_secret_version" "redis_password" {
  count = contains(local.gcp_secret_ids, local.redis_password_secret_id) ? 1 : 0

  secret      = google_secret_manager_secret.this[local.redis_password_secret_id].id
  secret_data = random_password.redis.result
}

resource "google_secret_manager_secret" "this" {
  for_each = toset(local.gcp_secret_ids)

  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = {
    for pair in local.gcp_workload_secret_pairs :
    "${pair.vm_name}/${pair.secret_id}" => pair
  }

  secret_id = google_secret_manager_secret.this[
    each.value.secret_id
  ].secret_id

  role = "roles/secretmanager.secretAccessor"

  member = "serviceAccount:${module.vm.vms[
    each.value.vm_name
  ].service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.gcp_secret_version_writers

  secret_id = google_secret_manager_secret.this[
    each.value.secret_id
  ].secret_id

  role   = "roles/secretmanager.secretVersionAdder"
  member = each.value.member
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.aws_secret_ids)

  name = each.value

  tags = merge(
    local.common_labels,
    {
      managed_by = "terraform"
      cloud      = "aws"
    },
  )
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = {
    for name, workload in local.aws_workload_vms :
    name => workload
    if length(local.effective_secret_mappings[workload.role]) > 0
  }

  name = "${local.resource_prefix}-${each.key}-secret-access"

  role = module.aws_vm.vms[
    each.key
  ].iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue",
        ]

        Resource = [
          for secret_id in sort(
            distinct(values(local.effective_secret_mappings[each.value.role]))
          ) :
          aws_secretsmanager_secret.this[secret_id].arn
        ]
      }
    ]
  })
}

resource "aws_secretsmanager_secret_version" "managed_database_password" {
  count = local.database_mode == "managed" && local.managed_cloud == "aws" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this[local.managed_database_password_secret_ids[0]].id
  secret_string = random_password.managed_database[0].result
}

resource "aws_secretsmanager_secret_version" "managed_database_host" {
  count = local.database_mode == "managed" && local.managed_cloud == "aws" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this[local.managed_database_host_secret_id].id
  secret_string = module.aws_managed_database[0].host
}

resource "aws_secretsmanager_secret_version" "rabbitmq_password" {
  count = local.database_mode == "managed" && local.managed_cloud == "aws" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this[local.rabbitmq_password_secret_id].id
  secret_string = random_password.rabbitmq[0].result
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  count = contains(local.aws_secret_ids, local.redis_password_secret_id) ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this[local.redis_password_secret_id].id
  secret_string = random_password.redis.result
}
