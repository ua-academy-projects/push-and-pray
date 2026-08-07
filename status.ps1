$ErrorActionPreference = "Stop"
$machines = @("db", "backend", "fetcher", "ui")
$addresses = @{}

Write-Host "=== Vagrant machines ===" -ForegroundColor Cyan
vagrant status

Write-Host "`n=== Physical bridged LAN addresses ===" -ForegroundColor Cyan
foreach ($machine in $machines) {
    $ip = (vagrant ssh $machine -c "grep '^LAN_IP=' /etc/weatherflow/lan.env | cut -d= -f2").Trim()
    $addresses[$machine] = $ip
    Write-Host ("{0,-8} {1}" -f $machine, $ip)
}

Write-Host "`n=== Docker containers ===" -ForegroundColor Cyan
foreach ($machine in $machines) {
    Write-Host "--- $machine ---" -ForegroundColor Yellow
    vagrant ssh $machine -c "docker ps --format 'table {{.Names}}	{{.Status}}'"
}

Write-Host "`n=== LAN URLs (no localhost / no port forwarding) ===" -ForegroundColor Green
Write-Host "UI:                  http://$($addresses['ui']):5000"
Write-Host "Backend health:      http://$($addresses['backend']):5000/health"
Write-Host "RabbitMQ Management: http://$($addresses['db']):15672"
