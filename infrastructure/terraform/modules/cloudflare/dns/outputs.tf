output "summary" {
  description = "Which public names this deployment publishes, who publishes them, and the records Terraform created. managed_by is terraform in self-hosted Kubernetes mode and ansible in managed mode, where the load balancer the records point at is created by Traefik's Service and so has no name until deploy_cluster has run. entries is empty whenever Terraform created nothing, including when Cloudflare is disabled and DNS is managed by hand."
  value = {
    managed_by = local.self_hosted ? "terraform" : "ansible"
    enabled    = var.config.cloudflare.enabled
    zone       = var.config.cloudflare.zone_name
    hostnames = sort(compact(concat(
      [var.config.ingress.hostname],
      local.self_hosted ? [var.config.kubernetes.api_endpoint] : [],
      local.headlamp_published ? [var.config.headlamp.hostname] : [],
    )))
    entries = {
      for key, record in cloudflare_dns_record.entry : key => {
        id       = record.id
        hostname = record.name
        type     = record.type
        address  = record.content
        ttl      = record.ttl
        proxied  = record.proxied
      }
    }
  }
}

output "headlamp" {
  description = "The operator console's hostname and the address it must resolve to. managed is false when Cloudflare is disabled, the console is off, or managed Kubernetes is selected, in which case the record is created by hand or by deploy_cluster; see docs/headlamp.md. address is null in managed Kubernetes mode, where the load balancer's name is only known after deployment."
  value = {
    enabled  = var.config.headlamp.enabled
    hostname = local.headlamp_published ? var.config.headlamp.hostname : null
    address  = try(var.vm.vms[var.config.kubernetes.entry_node].public_ip, null)
    managed  = var.config.cloudflare.enabled && local.headlamp_published && local.self_hosted
  }
}
