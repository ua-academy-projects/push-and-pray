output "cloud_init" {
  description = "Rendered Tailscale cloud-init payload keyed by logical VM name."
  value = {
    for name, cloud_init in module.cloud_init : name => cloud_init.rendered
  }
  sensitive = true
}
