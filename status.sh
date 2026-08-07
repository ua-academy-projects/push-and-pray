#!/usr/bin/env bash
set -euo pipefail

machines=(db backend fetcher ui)

echo "=== Vagrant machines ==="
vagrant status

echo
echo "=== Physical bridged LAN addresses ==="
for machine in "${machines[@]}"; do
    ip="$(vagrant ssh "$machine" -c "grep '^LAN_IP=' /etc/weatherflow/lan.env | cut -d= -f2" 2>/dev/null | tr -d '\r' | tail -n 1)"
    printf '%-8s %s\n' "$machine" "${ip:-not available}"
done

echo
echo "=== Docker containers ==="
for machine in "${machines[@]}"; do
    echo "--- $machine ---"
    vagrant ssh "$machine" -c "docker ps --format 'table {{.Names}}\t{{.Status}}'" || true
done

ui_ip="$(vagrant ssh ui -c "grep '^LAN_IP=' /etc/weatherflow/lan.env | cut -d= -f2" 2>/dev/null | tr -d '\r' | tail -n 1)"
backend_ip="$(vagrant ssh backend -c "grep '^LAN_IP=' /etc/weatherflow/lan.env | cut -d= -f2" 2>/dev/null | tr -d '\r' | tail -n 1)"
db_ip="$(vagrant ssh db -c "grep '^LAN_IP=' /etc/weatherflow/lan.env | cut -d= -f2" 2>/dev/null | tr -d '\r' | tail -n 1)"

echo
echo "=== LAN URLs (no localhost / no port forwarding) ==="
echo "UI:                  http://${ui_ip}:5000"
echo "Backend health:      http://${backend_ip}:5000/health"
echo "RabbitMQ Management: http://${db_ip}:15672"
