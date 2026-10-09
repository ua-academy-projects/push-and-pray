terraform {
  required_providers {
    tailscale = {
      source = "tailscale/tailscale"
    }

    cloudinit = {
      source = "hashicorp/cloudinit"
    }
  }
}
