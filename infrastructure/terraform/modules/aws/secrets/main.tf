locals {
  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  vms_by_location = {
    for location in distinct([for vm in values(local.vms) : vm.location]) : location => {
      for name, vm in local.vms : name => vm if vm.location == location
    }
  }
  locations = {
    for location in keys(local.vms_by_location) : location => var.config.locations[location].aws
  }
  primary_location = var.config.vms.bastion.location

  secret_ids_by_location = {
    for location, vms in local.vms_by_location : location => distinct(flatten([
      for vm in values(vms) : values(vm.secret_mappings) if vm.role != "bastion"
    ]))
  }
  secret_instances = merge({}, [
    for location, secret_ids in local.secret_ids_by_location : {
      for secret_id in secret_ids :
      location == local.primary_location ? secret_id : "${location}/${secret_id}" => {
        location  = location
        secret_id = secret_id
      }
    }
  ]...)

  workloads_with_secrets = {
    for name, vm in local.vms : name => {
      location   = vm.location
      secret_ids = distinct(values(vm.secret_mappings))
    } if vm.role != "bastion" && length(vm.secret_mappings) > 0
  }

  all_secret_ids = distinct(flatten(values(local.secret_ids_by_location)))
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_instances

  region = local.locations[each.value.location].region
  name   = each.value.secret_id
  tags   = var.config.common_labels
}

data "aws_iam_policy_document" "workload_access" {
  for_each = local.workloads_with_secrets

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      for secret_id in each.value.secret_ids :
      aws_secretsmanager_secret.this[
        each.value.location == local.primary_location ? secret_id : "${each.value.location}/${secret_id}"
      ].arn
    ]
  }
}

resource "aws_iam_role_policy" "workload_access" {
  for_each = local.workloads_with_secrets

  name   = "${each.key}-secret-access"
  role   = var.iam_role_names[each.key]
  policy = data.aws_iam_policy_document.workload_access[each.key].json
}
