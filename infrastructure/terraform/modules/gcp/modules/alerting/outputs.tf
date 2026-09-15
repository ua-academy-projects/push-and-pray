output "notification_channel_id" {
  description = "The email channel every policy notifies."
  value       = google_monitoring_notification_channel.email.id
}
