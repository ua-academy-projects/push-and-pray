# Bastion module

Creates the single SSH entry point into the VPC: one small hardened instance in
the management subnet, a static external IP, a dedicated service account, and per
person public keys installed through instance metadata.

## What it creates

| Resource | Name | Purpose |
| --- | --- | --- |
| `google_compute_instance` | `<prefix>-bastion` | Jump host, `e2-micro`, Shielded VM |
| `google_compute_address` | `<prefix>-bastion-ip` | Static IP, so allow-lists survive rebuilds |
| `google_service_account` | `<prefix>-bastion-sa` | Dedicated identity with almost no permissions |
| `google_project_iam_member` | - | `logging.logWriter`, `monitoring.metricWriter` for the audit trail |

The firewall rules live in the [network module](../network/README.md). This
module only tags the instance (`network_tag`) so those rules match it.

## Hardening

`templates/sshd-hardening.sh.tftpl` runs at boot and is idempotent. It moves sshd
to `ssh_port`, and sets `PermitRootLogin no`, `PasswordAuthentication no`,
`AuthenticationMethods publickey`, `MaxAuthTries 3`, `LoginGraceTime 30` and
`LogLevel VERBOSE`. `AllowTcpForwarding` stays on - `ProxyJump` needs it - while
agent forwarding, X11 and tunnelling are off. The script also handles images that
start sshd through `ssh.socket`, and runs `sshd -t` before restarting, so a bad
config cannot lock the team out.

Instance metadata sets `block-project-ssh-keys = TRUE`: project-wide keys are
ignored, and the only way in is a key listed in this module.

## SSH keys

`ssh_users` is a map of `linux-username -> one public key`. Validation rejects
anything that is not exactly one OpenSSH **public** key line, and specifically
rejects text containing `PRIVATE KEY`.

**Private keys are never generated, accepted or stored by Terraform.** Each
person creates their own keypair locally and hands over the `.pub` half only.
The private half never leaves their machine, so it can never end up in the
repository or in Terraform state.

## Usage

```hcl
module "bastion" {
  source = "./modules/bastion"

  project_id = var.project_id
  region     = var.region
  zone       = var.zone

  subnetwork_id = module.network.management_subnet.id
  network_tag   = module.network.network_tags.bastion

  ssh_port  = 18832
  ssh_users = {
    tabula = file("~/keys/tabula.pub")
  }
}
```

Outputs: `bastion_public_ip`, `bastion_private_ip`, `bastion_name`,
`bastion_zone`, `bastion_network_tags`, `bastion_service_account`, `ssh_port`,
`ssh_users`, `bastion_ssh_command`, `bastion_proxy_jump_command`.

## Access procedure

### 1. The person requesting access

Generate a keypair (Ed25519, passphrase-protected) and send **only** the `.pub`
file:

```bash
ssh-keygen -t ed25519 -a 100 -C "tabula@laptop" -f ~/.ssh/oil_bastion
```

Send `~/.ssh/oil_bastion.pub` and the public egress address you will connect
from. Never send or paste `~/.ssh/oil_bastion`.

### 2. The infrastructure owner

Add one entry per person to `terraform.tfvars`, and add the source address to
`bastion_allowed_cidrs` (see the [network module](../network/README.md)):

```hcl
ssh_users = {
  tabula = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... tabula@laptop"
}
```

Open a PR, get it reviewed, then apply:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Metadata updates take effect within seconds - the instance is not recreated.

### 3. Connecting

```bash
terraform output bastion_ssh_command
ssh -i ~/.ssh/oil_bastion -p 18832 tabula@<bastion-public-ip>
```

Private instances are never reachable directly. Jump through the bastion:

```bash
ssh -i ~/.ssh/oil_bastion -J tabula@<bastion-public-ip>:18832 -p 18832 tabula@10.10.1.5
```

Or make it permanent in `~/.ssh/config`:

```
Host oil-bastion
  HostName <bastion-public-ip>
  User tabula
  Port 18832
  IdentityFile ~/.ssh/oil_bastion
  IdentitiesOnly yes

Host oil-private-*
  User tabula
  Port 18832
  IdentityFile ~/.ssh/oil_bastion
  IdentitiesOnly yes
  ProxyJump oil-bastion
```

Then `ssh oil-bastion`, or `ssh oil-private-app` after adding a `HostName` for it.

To reach the database from a laptop, forward the port through the chain instead
of opening it - the database accepts connections from application instances only:

```bash
ssh -N -L 5432:10.10.1.6:5432 oil-private-app
```

### 4. Revoking access

Remove the person's entry from `ssh_users` (and their CIDR from
`bastion_allowed_cidrs` if it was personal), then apply. Confirm with the
verification steps below that the key is gone.

## Verifying bastion access

**The bastion answers on the approved port, and only there.** The first command
must print an SSH banner, the second must time out:

```bash
nc -vz -w 5 $(terraform output -raw bastion_public_ip) 18832
nc -vz -w 5 $(terraform output -raw bastion_public_ip) 22
```

**Login works with the key and nothing else:**

```bash
ssh -i ~/.ssh/oil_bastion -p 18832 tabula@$(terraform output -raw bastion_public_ip) 'hostname; whoami'
```

**Password login is refused** - this must fail with `Permission denied (publickey)`:

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p 18832 tabula@$(terraform output -raw bastion_public_ip)
```

**sshd really listens on the approved port** (run on the bastion):

```bash
sudo ss -tlnp | grep sshd
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)'
```

Expected: `port 18832`, `permitrootlogin no`, `passwordauthentication no`,
`pubkeyauthentication yes`.

**The installed keys match `ssh_users`, and nothing else is there:**

```bash
terraform output ssh_users
gcloud compute instances describe oil-bastion --zone=europe-central2-a \
  --format='value(metadata.items.filter("key:ssh-keys").extract("value"))' | cut -d' ' -f1,3
```

**The private path only works through the bastion.** The first must fail (no
route from the internet), the second must succeed:

```bash
ssh -o ConnectTimeout=5 -p 18832 tabula@10.10.1.5
ssh -J tabula@$(terraform output -raw bastion_public_ip):18832 -p 18832 tabula@10.10.1.5 'hostname'
```

**Access from a non-approved address is refused.** From an address outside
`bastion_allowed_cidrs` (mobile hotspot, VPN off), the connection must time out
rather than prompt for anything.

**Sessions are auditable.** Firewall logging and the bastion's logging role make
each connection visible:

```bash
gcloud logging read \
  'logName=~"compute.googleapis.com%2Ffirewall" AND jsonPayload.rule_details.reference=~"oil-allow-ssh-to-bastion"' \
  --limit=10 --format='table(timestamp,jsonPayload.connection.src_ip,jsonPayload.disposition)'

ssh -p 18832 tabula@$(terraform output -raw bastion_public_ip) \
  'sudo journalctl -u ssh -n 50 | grep Accepted'
```
