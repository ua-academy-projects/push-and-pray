# Reverse proxy

Installs host-level Nginx on the UI VM, obtains a Let's Encrypt certificate
through Certbot's Cloudflare DNS plugin, and proxies HTTPS requests to the UI
container on `127.0.0.1:8080`. Port 80 redirects to HTTPS.

The role reads `hostname` and `acme_email` from the external project
configuration's `cloudflare` object. It reads `CLOUDFLARE_API_TOKEN` from the
Ansible controller environment and writes Certbot's renewal credential file on
the UI VM with root-only `0600` permissions. The token is never stored in the
repository or Terraform state.

When switching from the legacy IP-based deployment, the role stops and removes
the old Traefik Compose project before Nginx takes ownership of ports 80 and
443. Certbot's systemd timer performs automatic renewal and a deploy hook
reloads Nginx after a renewed certificate is installed.
