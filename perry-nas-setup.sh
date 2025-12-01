#!/bin/bash
# Perry-NAS Setup Script – Raspberry Pi OS Trixie Version (v2.0)
# Fokus: PHP 8.4, Stabilität des Webinterfaces und UUID-Nutzung
set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_perry() { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Banner
echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#              PERRY-NAS (V2.0)            #${NC}"
echo -e "${PURPLE}#    Raspberry Pi 5 NAS Setup (Trixie)     #${NC}"
echo -e "${PURPLE}#     mit PCIe SATA & Webinterface         #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# Root Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen: sudo $0"
    exit 1
fi

# --- 1. System und Benutzer-Konfiguration ---
print_perry "1. Benutzer-Konfiguration und Hostname"
read -p "Benutzername für NAS und Samba (z.B. nasuser): " PERRY_USER
PERRY_HOSTNAME="perry-nas"

echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts
print_success "Hostname gesetzt: $PERRY_HOSTNAME"

# System Update
print_perry "2. System-Aktualisierung und Pakete installieren"
apt update
apt full-upgrade -y
apt autoremove -y

# PHP 8.4 ist hier als Beispiel gesetzt; falls nicht verfügbar, bitte auf 8.3 ändern!
PHP_VERSION="8.4"
apt install -y parted nginx php${PHP_VERSION}-fpm php${PHP_VERSION}-cli samba ufw curl bc hdparm
print_success "Alle notwendigen Pakete (inkl. PHP ${PHP_VERSION}) installiert."

# --- 2. Festplatte partitionieren und mounten (mit UUID) ---
print_perry "3. PCIe SATA Hardware-Setup und Partitionierung"
lsblk
read -p "Bitte Device Name der SATA-Platte (z.B. sda): " DISK

if [ ! -e "/dev/$DISK" ]; then
    print_error "Gerät /dev/$DISK existiert nicht."
    exit 1
fi

read -p "ALLE DATEN auf /dev/$DISK löschen? (ja/NEIN): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
    print_error "Abbruch."
    exit 1
fi

# Unmounten (falls gemountet) und Formatieren
umount "/dev/${DISK}"* 2>/dev/null || true
print_info "Partition wird angelegt und formatiert..."
parted /dev/$DISK --script mklabel gpt
parted /dev/$DISK --script mkpart primary ext4 0% 100%
mkfs.ext4 -F /dev/${DISK}1

# UUID ermitteln und fstab setzen (sehr wichtig für Stabilität!)
DISK_UUID=$(blkid -s UUID -o value /dev/${DISK}1)
print_info "Ermittelte UUID für fstab: $DISK_UUID"

mkdir -p /mnt/perry-nas
echo "UUID=$DISK_UUID /mnt/perry-nas ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
mount -a
print_success "Festplatte eingerichtet und via UUID in fstab eingetragen!"

# --- 3. Benutzer und Berechtigungen ---
print_perry "4. Benutzer erstellen und Berechtigungen setzen"
if ! id "$PERRY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$PERRY_USER"
    echo "Passwort für $PERRY_USER:";
    passwd "$PERRY_USER"
fi

# Setze Berechtigungen für das NAS-Mount (Eigentümer ist NAS-User)
chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas # Gut für Samba-Freigaben

# --- 4. Samba Konfiguration ---
print_perry "5. Samba wird konfiguriert..."
cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS
   security = user
   map to guest = bad user
   server min protocol = SMB2
   server max protocol = SMB3

[Perry-NAS]
   path = /mnt/perry-nas
   browseable = yes
   writable = yes
   valid users = $PERRY_USER
   force user = $PERRY_USER
   create mask = 0775
   directory mask = 0775
EOF

print_info "Samba Passwort für $PERRY_USER setzen..."
smbpasswd -a "$PERRY_USER"

systemctl enable smbd
systemctl restart smbd
print_success "Samba läuft."

# --- 5. Webinterface (Nginx & PHP) ---
print_perry "6. Webinterface-Konfiguration (Nginx und PHP-FPM)"
rm -f /var/www/html/index.nginx-debian.html

# WICHTIG: Korrekte Berechtigungen für Nginx/PHP-FPM, um Dateien zu lesen
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Nginx Konfiguration (mit optimierter PHP-Socket-Pfad-Handhabung)
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.php index.html index.htm; # Index.htm hinzugefügt

    location / {
        try_files \$uri \$uri/ =404;
    }

    # WICHTIG: Sicherstellen, dass der fastcgi_pass-Pfad korrekt ist.
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

# Webinterface Status-Datei (index.php)
cat > /var/www/html/index.php << 'EOF'
<?php
// PHP-Sicherheit: Nur die Ausgabe von Statusinformationen, keine Nutzereingaben verarbeitet
$disk_status = shell_exec('df -h /mnt/perry-nas');
$ram_status = shell_exec('free -h');
$load_avg = print_r(sys_getloadavg(), true);
?>
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Perry-NAS Status</title></head>
<body style="font-family:Arial;background:#eee;padding:20px;">
<h1>🍐 Perry-NAS Status</h1>
<pre>
Hostname: <?php echo shell_exec('hostname'); ?>
Uptime: <?php echo shell_exec('uptime -p'); ?>

--- Speicherstatus ---
Festplatte (/mnt/perry-nas):
<?php echo $disk_status; ?>

RAM:
<?php echo $ram_status; ?>

Last (Load Average):
<?php echo $load_avg; ?>
</pre>
</body></html>
EOF

systemctl restart nginx
systemctl restart php${PHP_VERSION}-fpm
print_success "Webinterface (Nginx und PHP-FPM) neu gestartet."

# --- 6. Firewall Konfiguration ---
print_perry "7. Firewall (UFW) wird konfiguriert"
ufw --force enable
ufw allow ssh
ufw allow http
ufw allow samba
ufw status verbose

# --- 7. Finaler Status ---
print_perry "8. Perry-NAS Abschlussbericht"
nginx -t && print_success "Nginx Konfiguration OK"

print_info "Festplatten-Performance (Kurztest):"
hdparm -Tt /dev/${DISK}1 | head -5 || true

PERRY_IP=$(hostname -I | awk '{print $1}')
print_success "PERRY-NAS Setup abgeschlossen!"
print_info "Webinterface ist verfügbar unter: http://$PERRY_IP/"
print_info "NAS-Freigabe (Samba) ist erreichbar unter: //$PERRY_HOSTNAME/Perry-NAS"