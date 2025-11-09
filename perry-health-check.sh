#!/bin/bash
# Perry-NAS Health Check Script

set -e

# Perry-NAS Farben
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${PURPLE}🍐 Perry-NAS Health Check${NC}"
echo "================================"

# System Status
echo -e "\n${PURPLE}📊 System Status:${NC}"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Last Boot: $(who -b | awk '{print $3, $4}')"

# Dienst Status
echo -e "\n${PURPLE}🔧 Dienst Status:${NC}"
services=("smbd" "nginx" "php8.3-fpm" "smartd")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo -e "✅ $service: ${GREEN}Aktiv${NC}"
    else
        echo -e "❌ $service: ${RED}Inaktiv${NC}"
    fi
done

# Festplatten Status
echo -e "\n${PURPLE}💾 Festplatten Status:${NC}"
df -h /mnt/perry-nas

# S.M.A.R.T. Status
echo -e "\n${PURPLE}❤️  S.M.A.R.T. Status:${NC}"
if command -v smartctl &> /dev/null; then
    for disk in /dev/sd*; do
        if [ -b "$disk" ] && [[ "$disk" =~ /dev/sd[a-z]$ ]]; then
            echo -n "$disk: "
            smartctl -H $disk 2>/dev/null | grep "SMART overall-health" | awk '{print $6}' || echo "Nicht verfügbar"
        fi
    done
else
    echo "smartctl nicht installiert"
fi

# Temperatur
echo -e "\n${PURPLE}🌡️  Temperaturen:${NC}"
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    echo "CPU: $((temp/1000))°C"
else
    echo "CPU Temperatur: Nicht verfügbar"
fi

# Netzwerk
echo -e "\n${PURPLE}📡 Netzwerk:${NC}"
echo "IP: $(hostname -I)"

echo -e "\n${GREEN}🍐 Perry-NAS Health Check abgeschlossen${NC}"