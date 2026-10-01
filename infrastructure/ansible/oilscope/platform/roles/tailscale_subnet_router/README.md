# Tailscale subnet router

Configures a bastion to advertise its cloud VPC/VNet CIDR. Set
`OILSCOPE_TAILSCALE_AUTH_KEY` in the controller environment. The tagged key and
the tailnet policy are external secrets and must not be committed.
