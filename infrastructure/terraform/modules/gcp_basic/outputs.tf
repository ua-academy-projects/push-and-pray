output "service_account_emails" {
  description = "Service account emails keyed by account name."

  value = {
    for name, account in google_service_account.accounts :
    name => account.email
  }
}

output "secret_ids" {
  description = "Secret Manager resource IDs keyed by configured secret ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.secrets :
    secret_id => secret.id
  }
}
