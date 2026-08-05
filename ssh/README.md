# AirAware SSH access

Vagrant always manages its own `vagrant` account and private key for provisioning and recovery:

```powershell
vagrant ssh backend
```

The project can additionally configure a personal public key for an `airaware` login on every VM.

## Generate a key on Windows

```powershell
ssh-keygen -t ed25519 -a 100 -f "$HOME\.ssh\airaware_ed25519" -C "airaware-vagrant"
```

Never commit the private key.

## Configure Vagrant

Add a public-key path to the root `.env`:

```dotenv
AIRAWARE_SSH_USER=airaware
AIRAWARE_SSH_PUBLIC_KEY_PATH=C:/Users/your-name/.ssh/airaware_ed25519.pub
```

Forward slashes avoid Windows dotenv escaping surprises. Alternatively, export the public key for the current PowerShell session:

```powershell
$env:AIRAWARE_SSH_PUBLIC_KEY = (
    Get-Content "$HOME\.ssh\airaware_ed25519.pub" -Raw
).Trim()
```

Explicit environment variables override the root `.env`.

## Provision SSH access

For all machines:

```powershell
vagrant provision --provision-with ssh-access
```

For one machine:

```powershell
vagrant provision backend --provision-with ssh-access
```

If no public key is configured, the provisioner exits without changing personal-key access and `vagrant ssh` remains available.

## Configure aliases

Copy the relevant entries from `ssh/config.example` into `$HOME\.ssh\config`, or include that file from your main OpenSSH configuration. Update `HostName` values if the network prefix differs from `192.168.18`.

Then connect with:

```powershell
ssh airaware-frontend
ssh airaware-backend
ssh airaware-fetcher
ssh airaware-infrastructure
```

The configured account receives passwordless sudo and Docker-group membership for lab administration. Keep the private key protected and use this feature only on a trusted LAN.
