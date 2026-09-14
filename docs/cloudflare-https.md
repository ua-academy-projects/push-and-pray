# Cloudflare DNS and UI HTTPS

The production UI endpoint uses Cloudflare DNS in front of an Nginx reverse
proxy on the UI VM. Terraform manages the proxied DNS A record and the
Cloudflare `Full (strict)` SSL mode. Ansible installs Nginx and Certbot, obtains
a public Let's Encrypt certificate through a Cloudflare DNS-01 challenge, and
keeps the certificate renewed.

```text
Browser --HTTPS--> Cloudflare --HTTPS--> Nginx :443 --HTTP--> 127.0.0.1:8080
```

The UI container publishes port 8080 only on the VM loopback interface. AWS and
GCP firewall rules expose only ports 80 and 443 for a Cloudflare-enabled UI.
Nginx redirects port 80 requests to HTTPS.

## Cloudflare prerequisites

The domain must already be added as an active Cloudflare zone. Copy the Zone ID
from **Cloudflare dashboard → domain → Overview → API**.

Create a scoped API token restricted to that zone with these permissions:

- `Zone / DNS / Edit` for the Terraform A record and Certbot DNS-01 challenge;
- `Zone / Zone Settings / Edit` for `Full (strict)`;
- `Zone / Zone / Read` for zone discovery performed by the provider and Certbot.

Export the token in the shell that runs both Terraform and Ansible:

```sh
export CLOUDFLARE_API_TOKEN="replace-with-a-scoped-token"
```

The token is not part of project configuration, Terraform code, Terraform
state, or the repository. Ansible writes it to
`/etc/letsencrypt/cloudflare.ini` on the UI VM with mode `0600`, because Certbot
needs the credential for unattended renewals.

## Project configuration

Add this root-level object to `project-config.json`:

```json
"cloudflare": {
  "enabled": true,
  "zone_id": "replace-with-the-32-character-zone-id",
  "hostname": "isopenkoandrii.pp.ua",
  "proxied": true,
  "acme_email": "replace-with-your-email@example.com"
}
```

Keep `network.ui_public_ports` set to both HTTP and HTTPS:

```json
"ui_public_ports": [80, 443]
```

The UI VM must have `assign_public_ip: true`. Terraform selects the public IP
from the existing AWS Elastic IP or GCP static external IP output according to
the UI VM's configured cloud; no public IP is stored in the JSON configuration.

## Terraform

Run from the repository root:

```sh
terraform -chdir=infrastructure/terraform init

terraform -chdir=infrastructure/terraform plan \
  -var="project_config_path=../../project-config.json"

terraform -chdir=infrastructure/terraform apply \
  -var="project_config_path=../../project-config.json"
```

Terraform creates `isopenkoandrii.pp.ua` as a proxied A record pointing to the
UI public IP and sets the zone SSL mode to `strict`.

## Ansible

Ansible executes the installed `oilscope.platform` collection. Build and
install it after changing or cloning the collection:

```sh
cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
cd ../../../..
```

Export the existing private GHCR credentials and the Cloudflare token in the
same shell, then deploy the UI:

```sh
export GHCR_USERNAME="replace-with-your-github-login"
export GHCR_TOKEN="replace-with-a-token-that-can-read-packages"
export CLOUDFLARE_API_TOKEN="replace-with-a-scoped-cloudflare-token"

ansible-playbook \
  -i infrastructure/ansible/inventory/oilscope.yml \
  infrastructure/ansible/oilscope/platform/playbooks/ui.yml
```

The role installs `nginx`, `certbot`, and
`python3-certbot-dns-cloudflare`. Certbot's systemd timer renews the certificate
and its deploy hook reloads Nginx after a successful renewal.

Open the application at <https://isopenkoandrii.pp.ua>. A request to
`http://isopenkoandrii.pp.ua` is redirected to HTTPS by Nginx.

## One-time manual step

If the domain is not already delegated to Cloudflare, replace the domain's
authoritative nameservers at the registrar with the two nameservers assigned by
Cloudflare. Terraform cannot perform this registrar-side delegation. Wait for
the Cloudflare zone to become active before requesting the certificate.
