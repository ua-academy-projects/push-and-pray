# Vagrant Deployment Guide

## 1. Overview

AirAware is deployed with one Vagrant multi-machine environment containing four VirtualBox VMs:

| Machine | Role | Address | Port |
|---|---|---:|---:|
| `frontend` | Flask dashboard | `192.168.50.210` | `5000` |
| `backend` | FastAPI application API | `192.168.50.211` | `8001` |
| `fetcher` | Open-Meteo collector | `192.168.50.212` | `8000` |
| `database` | PostgreSQL | `192.168.50.213` | `5432` |

The Vagrantfile uses:

- a machine configuration hash;
- loops to generate VM definitions;
- helper methods;
- validation;
- conditional provisioning;
- one common provisioner;
- one shared application provisioner;
- a dedicated database provisioner.

## 2. Prerequisites

Install:

```text
Vagrant 2.4+
VirtualBox 7.x
Git
```

Verify:

```powershell
vagrant --version
VBoxManage --version
git --version
```

## 3. Network requirements

The current configuration expects:

```text
LAN subnet: 192.168.50.0/24
Gateway:    192.168.50.1
Bridge:     Intel(R) Wi-Fi 6 AX200 160MHz
```

Before deployment:

1. Confirm that `.210`–`.213` are unused.
2. Confirm they are outside the router DHCP pool or reserved.
3. Confirm the selected bridge adapter is active.
4. Confirm client isolation is disabled on the Wi-Fi network.

List bridged interfaces:

```powershell
VBoxManage list bridgedifs
```

Test candidate addresses:

```powershell
$addresses = @(
    "192.168.50.210",
    "192.168.50.211",
    "192.168.50.212",
    "192.168.50.213"
)

foreach ($address in $addresses) {
    Test-Connection -ComputerName $address -Count 2 -Quiet
}
```

Also inspect the router’s connected-device and DHCP pages.

## 4. Environment configuration

The following host environment variables are supported:

```text
AIRAWARE_VAGRANT_BOX
AIRAWARE_NETWORK_PREFIX
AIRAWARE_NETMASK
AIRAWARE_BRIDGE_ADAPTER
AIRAWARE_DB_NAME
AIRAWARE_DB_USER
AIRAWARE_DB_PASSWORD
```

Example:

```powershell
$env:AIRAWARE_NETWORK_PREFIX = "192.168.50"
$env:AIRAWARE_NETMASK = "255.255.255.0"
$env:AIRAWARE_BRIDGE_ADAPTER = "Intel(R) Wi-Fi 6 AX200 160MHz"
$env:AIRAWARE_DB_NAME = "airaware"
$env:AIRAWARE_DB_USER = "airaware_user"
$env:AIRAWARE_DB_PASSWORD = "replace-with-a-strong-password"
```

These variables apply to the current PowerShell session.

## 5. Validate the configuration

From the repository root:

```powershell
vagrant validate
vagrant status
```

Expected before the first run:

```text
database   not created
backend    not created
fetcher    not created
frontend   not created
```

## 6. Deploy the environment

```powershell
vagrant up --provider=virtualbox
```

Expected provisioning order:

```text
database
backend
fetcher
frontend
```

Provisioning performs:

### All VMs

- installs common diagnostic tools;
- creates the `airaware` system user;
- writes local hostname mappings;
- creates `/opt/airaware`;
- records machine metadata.

### Database VM

- installs PostgreSQL;
- configures the database listener;
- restricts application access to the Backend VM;
- creates the role and database;
- executes `backend-service/database/init.sql`;
- verifies database objects.

### Application VMs

- installs Python and virtual-environment support;
- copies service code to `/opt/airaware`;
- creates a Python virtual environment;
- installs dependencies;
- generates `.env`;
- creates a systemd service;
- starts and verifies the service.

## 7. Validate the deployment

Check VM state:

```powershell
vagrant status
```

Check IP connectivity:

```powershell
ping 192.168.50.210
ping 192.168.50.211
ping 192.168.50.212
ping 192.168.50.213
```

Check ports:

```powershell
Test-NetConnection 192.168.50.210 -Port 5000
Test-NetConnection 192.168.50.211 -Port 8001
Test-NetConnection 192.168.50.212 -Port 8000
Test-NetConnection 192.168.50.213 -Port 5432
```

Check HTTP endpoints:

```powershell
Invoke-RestMethod http://192.168.50.210:5000/health
Invoke-RestMethod http://192.168.50.210:5000/health/ready

Invoke-RestMethod http://192.168.50.211:8001/health
Invoke-RestMethod http://192.168.50.211:8001/health/ready

Invoke-RestMethod http://192.168.50.212:8000/health
Invoke-RestMethod http://192.168.50.212:8000/health/ready
```

Open:

```text
Frontend: http://192.168.50.210:5000
Backend Swagger: http://192.168.50.211:8001/docs
Fetcher Swagger: http://192.168.50.212:8000/docs
```

## 8. Validate from another physical device

Connect another device to the same home LAN.

Test:

```powershell
ping 192.168.50.210
ping 192.168.50.211
ping 192.168.50.212
ping 192.168.50.213
```

Open:

```text
http://192.168.50.210:5000
```

No router port forwarding is required.

## 9. Reprovisioning

After changing Backend code:

```powershell
vagrant provision backend
```

After changing Fetcher code:

```powershell
vagrant provision fetcher
```

After changing Frontend code:

```powershell
vagrant provision frontend
```

After changing database initialisation:

```powershell
vagrant provision database
```

The application provisioner:

- copies current source files;
- updates dependencies;
- rewrites `.env`;
- restarts the corresponding systemd service.

## 10. Starting and stopping

Stop safely:

```powershell
vagrant halt
```

Start again:

```powershell
vagrant up
```

Suspend:

```powershell
vagrant suspend
```

Resume:

```powershell
vagrant resume
```

## 11. Destroying the environment

```powershell
vagrant destroy -f
```

This deletes:

- all VMs;
- PostgreSQL data inside the Database VM;
- installed packages;
- Python environments;
- generated service configuration.

It does not delete repository files.

## 12. Fresh reproducibility test

The final deployment test is:

```powershell
vagrant destroy -f
vagrant up --provider=virtualbox
```

After completion, verify:

- all four VMs are running;
- the database schema exists;
- city configuration exists;
- systemd services are active;
- the Fetcher can create measurements;
- the Frontend displays data.

## 13. Moving to another LAN

When moving from one network to another, update or override:

```text
network prefix
netmask
bridge adapter
```

Example:

```powershell
$env:AIRAWARE_NETWORK_PREFIX = "192.168.88"
$env:AIRAWARE_NETMASK = "255.255.255.0"
$env:AIRAWARE_BRIDGE_ADAPTER = "Intel(R) Wi-Fi 6 AX200 160MHz"
```

The VM suffixes remain:

```text
210
211
212
213
```

Recreate VMs after changing network settings:

```powershell
vagrant destroy -f
vagrant up
```

Confirm the new addresses are unused before deployment.

## 14. Security note

The VMs are bridged directly onto the LAN. Use this deployment only on a trusted home or lab network.

Do not expose the VM ports to the public internet through router port forwarding.
