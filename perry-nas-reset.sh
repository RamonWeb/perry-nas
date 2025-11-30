#!/bin/bash
# perry-nas-reset.sh – Perry-NAS zurücksetzen (DATENSCHONEND!)
# Entfernt Konfigurationen, hält aber Festplattendaten erhalten

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_perry() { echo -e "${PURPLE}[PERRY-RESET]${NC} $1"; }
print_ok() { echo -e "${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Bitte als root ausführen: sudo $0${NC}"
    exit 1
fi

print_perry "Perry-NAS Reset (DATENSCHONEND – Festplattendaten bleiben erhalten)"

read -p "⚠️  Möchten Sie das Perry-NAS-Setup wirklich zurücksetzen? (j/N): " CONFIRM
[[ ! $CONFIRM =~ ^[Jj]$ ]] && { echo "Abbruch."; exit 0; }

# --------------------------
# 1. Dienste stoppen
# --------------------------
print_perry "Stoppe Dienste..."
systemctl stop nginx smbd php8.4-fpm smartd 2>/dev/null || true

# --------------------------
# 2. Konfigurationen entfernen
# --------------------------
print_perry "Entferne Konfigurationen..."

# Samba
rm -f /etc/samba/smb.conf
systemctl disable smbd 2>/dev/null || true

# Nginx
rm -f /etc/nginx/sites-enabled/default
systemctl disable nginx 2>/dev/null || true

# PHP-FPM
systemctl disable php8.4-fpm 2>/dev/null || true

# S.M.A.R.T.
rm -f /etc/smartd.conf
systemctl disable smartd 2>/dev/null || true

# fstab-Eintrag (aber NICHT die Daten löschen!)
sed -i '/perry-nas/d' /etc/fstab
umount /mnt/perry-nas 2>/dev/null || true

# Web-Root leeren
rm -rf /var/www/html/*

# E-Mail-Skripte (optional)
rm -rf /home/*/perry-nas/scripts
rm -f /home/*/.perry-nas-email.conf

# sudoers-Regel
rm -f /etc/sudoers.d/perry-smartctl

# --------------------------
# 3. Bereinige Benutzer (optional)
# ------------------
# Benutzer NICHT löschen, da Daten unter /home/ liegen könnten
# Aber Samba-Passwort zurücksetzen:
smbpasswd -x perry 2>/dev/null || true

# --------------------------
# 4. Cron-Jobs entfernen
# --------------------------
for user in /home/*; do
    username=$(basename "$user")
    crontab -u "$username" -l 2>/dev/null | grep -v "perry-nas" | crontab -u "$username" - 2>/dev/null || true
done

# --------------------------
# 5. Neustart empfehlen
# --------------------------
print_ok "Perry-NAS wurde zurückgesetzt – Daten auf /mnt/perry-nas sind erhalten!"
print_warn "💡 Empfehlung: Führen Sie nach dem Neustart das Setup-Skript erneut aus."

read -p "Möchten Sie das System jetzt neustarten? (j/N): " REBOOT
[[ $REBOOT =~ ^[Jj]$ ]] && reboot
