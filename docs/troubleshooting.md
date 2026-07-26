# AirAware Troubleshooting

## 1. Vagrant cannot find the bridge adapter

### Symptom

Vagrant reports that the configured bridge interface does not exist.

### Diagnostics

```powershell
VBoxManage list bridgedifs
```

### Resolution

Set the exact active adapter name:

```powershell
$env:AIRAWARE_BRIDGE_ADAPTER = "Intel(R) Wi-Fi 6 AX200 160MHz"
vagrant up
```

Do not select a Hyper-V virtual adapter unless it is intentionally your active network path.

---

## 2. VM does not receive the expected LAN address

### Diagnostics

```powershell
vagrant ssh frontend -c "ip -br address"
vagrant ssh frontend -c "ip route"
```

### Common causes

- wrong network prefix;
- wrong bridge adapter;
- IP conflict;
- unsupported or restricted Wi-Fi bridging;
- stale VM network configuration.

### Resolution

Confirm LAN settings:

```powershell
ipconfig
```

Recreate the affected VM:

```powershell
vagrant destroy frontend -f
vagrant up frontend
```

---

## 3. Another device cannot reach the VMs

### Diagnostics

From the host:

```powershell
ping 192.168.50.210
```

From the second device:

```powershell
ping 192.168.50.210
Test-NetConnection 192.168.50.210 -Port 5000
```

### Common causes

- guest Wi-Fi;
- AP isolation;
- client isolation;
- firewall rules;
- second device connected to another subnet.

### Resolution

Connect both devices to the same non-guest LAN and disable client isolation in the router.

---

## 4. VM cannot access the internet

### Diagnostics

```bash
ip route
ping -c 3 1.1.1.1
getent hosts open-meteo.com
curl -I https://open-meteo.com
```

### Interpretation

- IP ping fails: routing problem.
- IP ping succeeds but DNS fails: DNS problem.
- DNS succeeds but HTTPS fails: firewall or TLS problem.

The default Vagrant NAT adapter should normally provide internet access.

---

## 5. Provisioning fails during `apt-get update`

### Diagnostics

Rerun:

```powershell
vagrant provision backend
```

Inside the VM:

```bash
sudo apt-get update
```

### Common causes

- temporary repository failure;
- no internet access;
- another package-manager process running;
- DNS failure.

### Resolution

Wait and reprovision. Check:

```bash
ps aux | grep -E 'apt|dpkg'
sudo dpkg --configure -a
```

---

## 6. Shell provisioner fails with strange syntax errors

### Common cause

Windows CRLF line endings.

### Resolution

Ensure `.gitattributes` contains:

```gitattributes
*.sh text eol=lf
Vagrantfile text eol=lf
```

Renormalise:

```powershell
git add --renormalize .
```

---

## 7. Frontend readiness returns 503

### Meaning

The Frontend cannot reach the Backend readiness endpoint.

### Diagnostics

```powershell
vagrant ssh frontend
```

```bash
curl -v http://192.168.50.211:8001/health/ready
ping -c 3 192.168.50.211
sudo journalctl -u airaware-frontend -n 100 --no-pager
```

### Common causes

- Backend service stopped;
- wrong Backend IP in Frontend `.env`;
- Backend listens only on `127.0.0.1`;
- network problem.

### Resolution

Backend must run with:

```text
--host 0.0.0.0 --port 8001
```

Restart:

```bash
sudo systemctl restart airaware-backend
```

---

## 8. Backend readiness returns 503

### Meaning

The Backend cannot connect to PostgreSQL.

### Diagnostics

```powershell
vagrant ssh backend
```

```bash
sudo journalctl -u airaware-backend -n 100 --no-pager
ping -c 3 192.168.50.213
nc -vz 192.168.50.213 5432
cat /opt/airaware/backend-service/.env
```

Do not share the database password in screenshots or logs.

### Common causes

- PostgreSQL stopped;
- wrong database password;
- incorrect URL encoding;
- PostgreSQL does not listen on the bridged address;
- `pg_hba.conf` does not allow the Backend IP;
- wrong database name or role.

---

## 9. PostgreSQL is not listening on the LAN address

### Diagnostics

On Database VM:

```bash
sudo ss -lntp | grep 5432
sudo grep -n "listen_addresses" /etc/postgresql/*/main/postgresql.conf
```

Expected listener:

```text
192.168.50.213:5432
```

Restart:

```bash
sudo systemctl restart postgresql
```

---

## 10. PostgreSQL rejects Backend authentication

### Diagnostics

On Database VM:

```bash
sudo tail -n 50 /var/log/postgresql/postgresql-*.log
sudo grep -n "AIRAWARE ACCESS" -A 3 /etc/postgresql/*/main/pg_hba.conf
```

Expected rule:

```text
host airaware airaware_user 192.168.50.211/32 scram-sha-256
```

Reload:

```bash
sudo systemctl reload postgresql
```

---

## 11. API Fetcher readiness returns 503

### Meaning

The Fetcher cannot reach the Backend.

### Diagnostics

```powershell
vagrant ssh fetcher
```

```bash
curl -v http://192.168.50.211:8001/health/ready
sudo journalctl -u airaware-fetcher -n 100 --no-pager
```

Check:

```bash
cat /opt/airaware/api-fetcher-service/.env
```

---

## 12. API Fetcher cannot reach Open-Meteo

### Diagnostics

```bash
curl -I https://air-quality-api.open-meteo.com
getent hosts air-quality-api.open-meteo.com
```

Check logs:

```bash
sudo journalctl -u airaware-fetcher -f
```

Stored dashboard data remains available even when Open-Meteo is unavailable.

---

## 13. Manual fetch creates no new rows

### Likely cause

Open-Meteo returned the same observation timestamp as the previous fetch.

The database unique constraint prevents duplicates.

Check:

```powershell
Invoke-RestMethod `
    -Method Post `
    -Uri http://192.168.50.212:8000/fetch
```

A result with `created: false` is expected within the same provider observation hour.

---

## 14. Graph has only one or a few points

### Cause

The Fetcher has not been running long enough to collect 12 or 24 hourly measurements.

### Resolution

Allow the service to run over time. Confirm scheduling:

```bash
sudo journalctl -u airaware-fetcher -n 200 --no-pager
```

---

## 15. A systemd service fails to start

### Diagnostics

```bash
sudo systemctl status airaware-backend --no-pager
sudo journalctl -u airaware-backend -n 100 --no-pager
```

Equivalent commands apply to Frontend and Fetcher.

Check:

- `WorkingDirectory`;
- generated `.env`;
- dependency installation;
- Python import errors;
- selected port;
- service user permissions.

After fixing source or provisioning:

```powershell
vagrant provision backend
```

---

## 16. Port is not reachable from the LAN

### Diagnostics

Inside the VM:

```bash
sudo ss -lntp
```

Expected:

```text
0.0.0.0:5000
0.0.0.0:8001
0.0.0.0:8000
```

A service bound to `127.0.0.1` is reachable only from inside its VM.

---

## 17. Static IP conflict

### Symptoms

- intermittent connectivity;
- ARP warnings;
- responses from the wrong device;
- VM address becomes unreachable.

### Diagnostics

```powershell
arp -a
ping 192.168.50.210
```

Inspect router connected clients.

### Resolution

Select addresses outside the DHCP pool or configure reservations. Update the Vagrant network configuration and recreate the VMs.

---

## 18. Vagrant SSH works but LAN address does not

Vagrant SSH normally uses the NAT adapter and a forwarded port. Therefore, SSH can work even when bridged networking is broken.

Inspect the bridged interface:

```powershell
vagrant ssh backend -c "ip -br address && ip route"
```

---

## 19. Reprovisioning does not apply network changes

Provisioning scripts do not recreate VirtualBox adapters.

For network changes:

```powershell
vagrant destroy -f
vagrant up
```

---

## 20. Database data disappeared

### Common cause

The Database VM was destroyed.

```powershell
vagrant destroy database -f
```

removes the VM disk and PostgreSQL data.

### Prevention

Create a backup before destroying:

```powershell
New-Item -ItemType Directory -Path backups -Force

vagrant ssh database -c "sudo -u postgres pg_dump -Fc airaware > /vagrant/backups/airaware.dump"
```
