#!/bin/bash
# Kompletter NAS-System-Reset

set -e

echo "=== KOMPLETTER NAS-SYSTEM-RESET ==="

# 1. Dienste stoppen
sudo systemctl stop smbd nginx php*-fpm 2>/dev/null || true

# 2. Samba komplett zurücksetzen
sudo apt remove --purge samba samba-common -y 2>/dev/null || true
sudo apt autoremove -y

# 3. Webserver zurücksetzen
sudo apt remove --purge nginx php-fpm php-cli -y 2>/dev/null || true

# 4. Mounts und fstab bereinigen
sudo umount /dev/sda* 2>/dev/null || true
sudo umount /mnt/nas 2>/dev/null || true
sudo cp /etc/fstab /etc/fstab.backup.reset
sudo grep -v "sda" /etc/fstab > /etc/fstab.tmp
sudo mv /etc/fstab.tmp /etc/fstab

# 5. Webverzeichnis leeren
sudo rm -rf /var/www/html/*

# 6. Alte Backups löschen
sudo rm -f /etc/samba/smb.conf.backup* 2>/dev/null || true
sudo rm -f /etc/fstab.backup* 2>/dev/null || true

# 7. Systemd Services bereinigen
sudo systemctl disable ensure-nas-mount.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ensure-nas-mount.service
sudo systemctl daemon-reload

echo "✅ Kompletter Reset abgeschlossen!"
echo "System ist jetzt frisch für neuen Test"