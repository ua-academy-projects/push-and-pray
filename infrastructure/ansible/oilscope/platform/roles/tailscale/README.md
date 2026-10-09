# Tailscale role

Verifies and enforces Tailscale settings after Terraform cloud-init has installed
and authenticated each VM. It can install the package as a recovery path, but
normal first-boot authentication is owned by Terraform.

The selected K3s subnet routers enable IPv4/IPv6 forwarding and advertise the
CIDRs passed in `tailscale_advertise_routes`. Every host accepts approved routes.
The role checks current state before changing anything.

An emergency manual run may provide `OILSCOPE_TAILSCALE_AUTH_KEY`. The value is
written only to a root-only file under `/run`, passed to `tailscale up` through
a `file:` reference and deleted immediately. The automated deployment does not
need this environment variable.

Required variables:

- `tailscale_hostname`: unique machine name in the tailnet;
- `tailscale_subnet_router`: whether this K3s server advertises cloud CIDRs;
- `tailscale_advertise_routes`: CIDRs advertised by the selected router.

See `docs/tailscale.md` for Terraform bootstrap and policy ownership.
