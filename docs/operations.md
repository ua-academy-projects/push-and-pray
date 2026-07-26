# AirAware Operations Guide

## 1. Daily workflow

Start the environment:

```powershell
vagrant up
```

Check status:

```powershell
vagrant status
```

Open the dashboard:

```text
http://192.168.50.210:5000
```

Stop the environment safely:

```powershell
vagrant halt
```

Destroying the VMs is not required for normal shutdown.

## 2. VM access

```powershell
vagrant ssh frontend
vagrant ssh backend
vagrant ssh fetcher
vagrant ssh database
```

Exit:

```bash
exit
```

## 3. Service status

### Frontend

```bash
sudo systemctl status airaware-frontend
```

### Backend

```bash
sudo systemctl status airaware-backend
```

### Fetcher

```bash
sudo systemctl status airaware-fetcher
```

### PostgreSQL

```bash
sudo systemctl status postgresql
```

## 4. Restart services

```bash
sudo systemctl restart airaware-frontend
sudo systemctl restart airaware-backend
sudo systemctl restart airaware-fetcher
sudo systemctl restart postgresql
```

## 5. Logs

Frontend:

```bash
sudo journalctl -u airaware-frontend -n 100 --no-pager
sudo journalctl -u airaware-frontend -f
```

Backend:

```bash
sudo journalctl -u airaware-backend -n 100 --no-pager
sudo journalctl -u airaware-backend -f
```

Fetcher:

```bash
sudo journalctl -u airaware-fetcher -n 100 --no-pager
sudo journalctl -u airaware-fetcher -f
```

PostgreSQL:

```bash
sudo journalctl -u postgresql -n 100 --no-pager
```

## 6. Health checks

Frontend:

```powershell
Invoke-RestMethod http://192.168.50.210:5000/health
Invoke-RestMethod http://192.168.50.210:5000/health/ready
```

Backend:

```powershell
Invoke-RestMethod http://192.168.50.211:8001/health
Invoke-RestMethod http://192.168.50.211:8001/health/ready
```

Fetcher:

```powershell
Invoke-RestMethod http://192.168.50.212:8000/health
Invoke-RestMethod http://192.168.50.212:8000/health/ready
```

## 7. Manual data fetch

Trigger a collection run:

```powershell
Invoke-RestMethod `
    -Method Post `
    -Uri http://192.168.50.212:8000/fetch
```

Check fetch status:

```powershell
Invoke-RestMethod http://192.168.50.212:8000/fetch/status
```

A second fetch within the same observation hour may return duplicate results. This is expected.

## 8. Database inspection

Connect to the Database VM:

```powershell
vagrant ssh database
```

List databases:

```bash
sudo -u postgres psql -l
```

Open the application database:

```bash
sudo -u postgres psql -d airaware
```

Useful SQL:

```sql
SELECT * FROM cities ORDER BY name;
```

```sql
SELECT
    c.code,
    c.name,
    m.observed_at,
    m.european_aqi,
    m.pm2_5,
    m.pm10
FROM air_quality_measurements AS m
JOIN cities AS c
    ON c.id = m.city_id
ORDER BY m.observed_at DESC, c.name;
```

Counts:

```sql
SELECT
    c.name,
    COUNT(m.id) AS measurement_count,
    MAX(m.observed_at) AS latest_observation
FROM cities AS c
LEFT JOIN air_quality_measurements AS m
    ON m.city_id = c.id
GROUP BY c.id, c.name
ORDER BY c.name;
```

Exit PostgreSQL:

```text
\q
```

## 9. Verify database access from Backend

Connect to Backend:

```powershell
vagrant ssh backend
```

Test TCP connectivity:

```bash
nc -vz 192.168.50.213 5432
```

Test application readiness:

```bash
curl http://192.168.50.211:8001/health/ready
```

## 10. Deploy code changes

After editing files on the host:

```powershell
vagrant provision frontend
vagrant provision backend
vagrant provision fetcher
```

Only reprovision the changed service when possible.

Check logs after deployment:

```powershell
vagrant ssh backend -c "sudo journalctl -u airaware-backend -n 50 --no-pager"
```

## 11. Recreate one VM

Example for Backend:

```powershell
vagrant destroy backend -f
vagrant up backend
```

Be careful with the Database VM. Destroying it deletes PostgreSQL data.

## 12. Backup PostgreSQL

Create a backup directory on the host:

```powershell
New-Item -ItemType Directory -Path backups -Force
```

From the Database VM, write a dump into the shared repository directory:

```powershell
vagrant ssh database -c "sudo -u postgres pg_dump -Fc airaware > /vagrant/backups/airaware.dump"
```

Restore into an existing empty database:

```powershell
vagrant ssh database -c "sudo -u postgres pg_restore -d airaware --clean --if-exists /vagrant/backups/airaware.dump"
```

Do not commit database dumps containing real data or credentials unless explicitly required.

## 13. Verify network communication

From Frontend:

```powershell
vagrant ssh frontend -c "ping -c 2 192.168.50.211"
```

From Fetcher:

```powershell
vagrant ssh fetcher -c "curl http://192.168.50.211:8001/health/ready"
```

From Backend:

```powershell
vagrant ssh backend -c "nc -vz 192.168.50.213 5432"
```

From another laptop:

```powershell
ping 192.168.50.210
```

## 14. Planned maintenance

Recommended routine:

```text
Daily:
- start with vagrant up
- confirm health endpoints
- stop with vagrant halt

After code changes:
- provision the changed VM
- check systemd status
- check logs
- test relevant endpoints

Before destructive changes:
- back up PostgreSQL
- commit source and provisioning changes
```
