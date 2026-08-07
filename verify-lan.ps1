$ErrorActionPreference = "Stop"
$machines = @("db", "backend", "fetcher", "ui")

Write-Host "Host adapters with a default gateway:" -ForegroundColor Cyan
Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -ne $null } |
    ForEach-Object {
        Write-Host ("  {0}: {1}/{2}, gateway {3}" -f `
            $_.InterfaceAlias,
            $_.IPv4Address.IPAddress,
            $_.IPv4Address.PrefixLength,
            $_.IPv4DefaultGateway.NextHop)
    }

Write-Host "`nVM bridged interfaces:" -ForegroundColor Cyan
foreach ($machine in $machines) {
    Write-Host "--- $machine ---" -ForegroundColor Yellow
    vagrant ssh $machine -c "weatherflow-lan-info"
}

Write-Host "`nThe proof is the second VM address from the router's LAN, not 10.0.2.15." -ForegroundColor Green
Write-Host "The project has no forwarded_port and is opened through the UI VM LAN address." -ForegroundColor Green
