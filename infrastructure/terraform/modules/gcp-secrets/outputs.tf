output "service_account_emails" {
  description = "Service account email addresses keyed by logical GCP VM name."
  value = {
    for name, service_account in google_service_account.vm : name => service_account.email
  }
}
