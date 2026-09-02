locals {
  gcp_workload_vms = {
    for name, workload in local.gcp_vms :
    name => workload
    if workload.role != "bastion"
  }

  aws_workload_vms = {
    for name, workload in local.aws_vms :
    name => workload
    if workload.role != "bastion"
  }

  gcp_secret_ids = distinct(flatten([
    for workload in values(local.gcp_workload_vms) :
    values(workload.secret_mappings)
  ]))

  aws_secret_ids = distinct(flatten([
    for workload in values(local.aws_workload_vms) :
    values(workload.secret_mappings)
  ]))

  gcp_workload_secret_pairs = flatten([
    for name, workload in local.gcp_workload_vms : [
      for secret_id in distinct(values(workload.secret_mappings)) : {
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

  member = "serviceAccount:${module.vm[
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
    if length(workload.secret_mappings) > 0
  }

  name = "${local.resource_prefix}-${each.key}-secret-access"

  role = module.aws_vm[
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
            distinct(values(each.value.secret_mappings))
          ) :
          aws_secretsmanager_secret.this[secret_id].arn
        ]
      }
    ]
  })
}