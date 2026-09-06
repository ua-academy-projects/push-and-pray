locals {
  # Same five scopes GCP expresses as network tags. On AWS a scope is a
  # security group the instance belongs to, and rules reference the group
  # instead of matching a tag string.
  scopes = ["bastion", "infra", "history", "fetcher", "ui"]

  workload_scopes = ["infra", "history", "fetcher", "ui"]

  database_client_scopes = ["fetcher", "history", "ui"]
}
