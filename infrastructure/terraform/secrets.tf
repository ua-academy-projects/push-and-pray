locals {
  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) : values(workload.secret_mappings)
  ]))

  gcp_secret_ids = distinct(flatten([
    for name, workload in local.gcp_secret_reading_vms : values(workload.secret_mappings)
  ]))

  aws_secret_ids = distinct(flatten([
    for name, workload in local.aws_secret_reading_vms : values(workload.secret_mappings)
  ]))

  workload_secret_pairs = flatten([
    for name, workload in local.gcp_secret_reading_vms : [
      for secret_id in distinct(values(workload.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  secret_version_writers = {
    for pair in setproduct(sort(local.gcp_secret_ids), var.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}

resource "google_secret_manager_secret" "this" {
  for_each  = toset(local.gcp_secret_ids)
  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = { for pair in local.workload_secret_pairs : "${pair.vm_name}/${pair.secret_id}" => pair }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.gcp_vm[each.value.vm_name].runtime_identity}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.aws_secret_ids)

  name        = each.value
  description = "Managed by Terraform from the project configuration"
  tags        = local.common_labels

  recovery_window_in_days = 7
}

data "aws_iam_policy_document" "workload_secret_access" {
  for_each = local.aws_secret_reading_vms

  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]

    resources = [
      for secret_id in distinct(values(each.value.secret_mappings)) :
      aws_secretsmanager_secret.this[secret_id].arn
    ]
  }
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = local.aws_secret_reading_vms

  name   = "${local.resource_prefix}-${each.key}-secret-access"
  role   = module.aws_vm[each.key].runtime_identity
  policy = data.aws_iam_policy_document.workload_secret_access[each.key].json
}

data "aws_iam_policy_document" "version_adder" {
  for_each = toset(length(var.secret_version_manager_arns) > 0 ? local.aws_secret_ids : [])

  statement {
    effect  = "Allow"
    actions = ["secretsmanager:PutSecretValue"]

    principals {
      type        = "AWS"
      identifiers = var.secret_version_manager_arns
    }

    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "version_adder" {
  for_each = toset(length(var.secret_version_manager_arns) > 0 ? local.aws_secret_ids : [])

  secret_arn = aws_secretsmanager_secret.this[each.value].arn
  policy     = data.aws_iam_policy_document.version_adder[each.value].json
}
