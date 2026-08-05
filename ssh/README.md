# AirAware SSH access

Vagrant keeps its own `vagrant` account and managed key for provisioning and recovery.
The project additionally configures an `airaware` login account with a user-provided
public key.

## Recommended setup on Windows

Run from PowerShell in the repository root:

```powershell
.\scripts\setup-ssh.ps1
vagrant provision
```

The helper script:

1. creates `~/.ssh/airaware_ed25519` when missing;
2. loads the public key into `AIRAWARE_SSH_PUBLIC_KEY`;
3. writes `~/.ssh/config.d/airaware`;
4. adds `Include ~/.ssh/config.d/*` to the main SSH config when needed.

Then connect with:

```powershell
ssh airaware-frontend
ssh airaware-backend
ssh airaware-fetcher
ssh airaware-infrastructure
```

## Manual setup

Generate a key:

```powershell
ssh-keygen -t ed25519 -a 100 -f "$HOME\.ssh\airaware_ed25519" -C "airaware-vagrant"
```

Load it before Vagrant provisioning:

```powershell
$env:AIRAWARE_SSH_PUBLIC_KEY = (
    Get-Content "$HOME\.ssh\airaware_ed25519.pub" -Raw
).Trim()
$env:AIRAWARE_SSH_USER = "airaware"
```

Copy `ssh/config.example` entries into your OpenSSH config and run:

```powershell
vagrant provision
```

Never commit the private key.
