locals {
  enabled = var.config.default_cloud == "aws" && try(var.config.managed_kubernetes, false)

  console_oidc_enabled = (
    local.enabled &&
    try(var.config.headlamp.enabled, false) &&
    try(var.config.headlamp.auth_mode, "token") == "oidc"
  )

  caller_assumed_role = try(
    regex("^arn:([^:]+):sts::([0-9]+):assumed-role/([^/]+)/", data.aws_caller_identity.current.arn),
    null
  )

  caller_principal = (
    local.caller_assumed_role == null
    ? data.aws_caller_identity.current.arn
    : "arn:${local.caller_assumed_role[0]}:iam::${local.caller_assumed_role[1]}:role/${local.caller_assumed_role[2]}"
  )

  admin_principals = local.enabled ? toset(concat(
    [local.caller_principal],
    try(var.config.kubernetes.eks.admin_principal_arns, []),
  )) : toset([])
}
