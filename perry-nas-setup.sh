#!/bin/bash
# Perry-NAS Setup Script – Raspberry Pi OS Trixie Version
# CLEAN VERSION: ohne SMART, mit PHP 8.4, mit finalem Statusreport am Ende

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
echo -e "${PURPLE}#              PERRY-NAS                   #${NC}"
echo -e "${PURPLE}#    Raspberry Pi 5 NAS Setup (Trixie)     #${NC}"
echo -e "${PURPLE}#     mit PCIe SATA & Webinterface         #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# Root Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen: sudo $0"
    exit 1
fi

# User Input
print_perry "Perry-NAS Benutzer-Konfiguration"
read -p "Benutzername: " PERRY_USER
PERRY_IP=$(hostname -I | awk '{print $1}')
PERRY_HOSTNAME="perry-nas"

echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts
print_success "Hostname gesetzt: $PERRY_HOSTNAME"

# System Update
print_perry "System wird aktualisiert..."
apt update
apt full-upgrade -y
apt autoremove -y

# Packages installieren
apt install -y parted nginx php8.4-fpm php8.4-cli samba ufw curl bc hdparm

# PCIe SATA
print_perry "PCIe SATA Hardwareprüfung"
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

umount "/dev/${DISK}"* 2>/dev/null || true

print_info "Partition wird angelegt..."
parted /dev/$DISK --script mklabel gpt
parted /dev/$DISK --script mkpart primary ext4 0% 100%
mkfs.ext4 -F /dev/${DISK}1

mkdir -p /mnt/perry-nas
echo "/dev/${DISK}1 /mnt/perry-nas ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
mount -a

# User erstellen
if ! id "$PERRY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$PERRY_USER"
    echo "Passwort für $PERRY_USER:";
    passwd "$PERRY_USER"
fi

chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

print_success "Festplatte eingerichtet!"

# Samba
print_perry "Samba wird konfiguriert..."
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

print_info "Samba Passwort setzen..."
smbpasswd -a "$PERRY_USER"

systemctl enable smbd
systemctl restart smbd

# Webinterface
print_perry "Webinterface wird installiert..."
rm -f /var/www/html/index.nginx-debian.html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

PHP_VERSION="8.4"
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }
}
EOF

# Webinterface File
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Perry-NAS Status</title></head>
<body style="font-family:Arial;background:#eee;padding:20px;">
<h1>🍐 Perry-NAS Status</h1>
<pre>
Hostname: <?php echo shell_exec('hostname'); ?>
Benutzer: <?php echo shell_exec('whoami'); ?>
Uptime: <?php echo shell_exec('uptime -p'); ?>

Festplatte:
<?php echo shell_exec('df -h /mnt/perry-nas'); ?>

RAM:
<?php echo shell_exec('free -h'); ?>

Load:
<?php print_r(sys_getloadavg()); ?>
</pre>
</body></html>
EOF

systemctl restart nginx
systemctl restart php${PHP_VERSION}-fpm

# Firewall
ufw --force enable
ufw allow ssh
ufw allow 80
ufw allow samba

# Finaler Status
print_perry "Perry-NAS Abschlussbericht"
nginx -t && print_success "Nginx OK"

print_info "Festplatten-Performance:"
hdparm -Tt /dev/${DISK}1 | head -5 || true

print_success "PERRY-NAS Setup abgeschlossen!"
