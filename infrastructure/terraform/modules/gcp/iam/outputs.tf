output "service_account_emails" {
  description = "Emails of each workload VM's dedicated service account, by VM key."
  value       = { for name, sa in google_service_account.workload : name => sa.email }
}
