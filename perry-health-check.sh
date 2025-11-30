#!/bin/bash
# perry-health-check.sh – Perry-NAS Gesundheitsprüfung
# Kompatibel mit Raspberry Pi 5 + PCIe SATA + HomeRacker

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_perry() { echo -e "${PURPLE}[PERRY-HEALTH]${NC} $1"; }
print_ok() { echo -e "${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_fail() { echo -e "${RED}❌ $1${NC}"; }

print_perry "Starte umfassenden Perry-NAS Health-Check..."

# --------------------------
# 1. Systembasis
# --------------------------
print_perry "1. Systeminformationen"
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
UPTIME=$(uptime -p)

echo "Hostname: $HOSTNAME"
echo "IP: $IP"
echo "Uptime: $UPTIME"
print_ok "Systembasis OK"

# --------------------------
# 2. Dienste prüfen
# --------------------------
print_perry "2. Dienste-Status"
SERVICES=("nginx" "smbd" "php8.4-fpm" "smartd")
ALL_OK=true

for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        print_ok "$svc: aktiv"
    else
        print_fail "$svc: inaktiv"
        ALL_OK=false
    fi
done

# --------------------------
# 3. Festplatten & Mount
# --------------------------
print_perry "3. Festplatten und Mount"
NAS_MOUNT="/mnt/perry-nas"

if mountpoint -q "$NAS_MOUNT"; then
    print_ok "Perry-NAS gemountet: $NAS_MOUNT"
else
    print_fail "Perry-NAS NICHT gemountet!"
    ALL_OK=false
fi

# Speichernutzung
df -h "$NAS_MOUNT"

# PCIe-Erkennung
PCI_DEVICES=$(lspci 2>/dev/null | grep -i sata || echo "Kein PCIe SATA erkannt")
echo "PCIe SATA: $PCI_DEVICES"

# --------------------------
# 4. S.M.A.R.T.-Status
# --------------------------
print_perry "4. S.M.A.R.T. Gesundheit"
DISKS=$(lsblk -dno NAME | grep -E '^(sd|nvme)' | head -n1)

if [ -n "$DISKS" ]; then
    DEV="/dev/$DISKS"
    if smartctl -H "$DEV" 2>/dev/null | grep -q "PASSED"; then
        TEMP=$(smartctl -A "$DEV" 2>/dev/null | awk '/Temperature_Celsius/ {print $10}')
        TEMP="${TEMP:-?}°C"
        print_ok "S.M.A.R.T.: $DEV – OK (Temperatur: $TEMP)"
    else
        print_fail "S.M.A.R.T.: $DEV – FEHLERHAFT!"
        ALL_OK=false
    fi
else
    print_warn "Keine Festplatte für S.M.A.R.T. gefunden"
fi

# --------------------------
# 5. Web-Interface Test
# --------------------------
print_perry "5. Web-Interface Verfügbarkeit"
if curl -s --head http://localhost/ | head -n1 | grep -q "200 OK"; then
    print_ok "Web-Interface erreichbar"
else
    print_fail "Web-Interface nicht erreichbar"
    ALL_OK=false
fi

# --------------------------
# 6. Samba-Test (lokal)
# --------------------------
print_perry "6. Samba-Freigabe (lokal)"
if smbclient -L localhost -N 2>/dev/null | grep -q "Perry-NAS"; then
    print_ok "Samba-Freigabe sichtbar"
else
    print_warn "Samba-Freigabe nicht lokal sichtbar (kann bei Auth normal sein)"
fi

# --------------------------
# 7. Firewall & Ports
# --------------------------
print_perry "7. Firewall & Ports"
PORTS=("22" "80" "445")
for port in "${PORTS[@]}"; do
    if ss -tuln | grep -q ":$port "; then
        print_ok "Port $port: geöffnet"
    else
        print_warn "Port $port: geschlossen"
    fi
done

# --------------------------
# Fazit
# --------------------------
echo ""
if [ "$ALL_OK" = true ]; then
    print_ok "🎉 Perry-NAS ist vollständig gesund und betriebsbereit!"
else
    print_fail "⚠️  Perry-NAS hat Warnungen oder Fehler – siehe oben."
fi

echo -e "\n${BLUE}Tipps:${NC}"
echo "  - Logs: sudo journalctl -u smbd -f"
echo "  - S.M.A.R.T.: sudo smartctl -a /dev/sda"
echo "  - Web-Error: sudo tail /var/log/nginx/error.log"
