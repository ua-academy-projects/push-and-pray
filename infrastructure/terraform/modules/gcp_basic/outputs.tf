output "service_account_emails" {
  description = "Service account emails keyed by account name."

  value = {
    for name, account in google_service_account.accounts :
    name => account.email
  }
}