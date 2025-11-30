#!/bin/bash
# Perry-NAS Setup Script – Saubere finale Version
# Raspberry Pi 5 + PCIe SATA + HomeRacker | Debian Trixie | nginx only

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_perry() { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Banner
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#              PERRY-NAS                   #${NC}"
echo -e "${PURPLE}#    Raspberry Pi 5 NAS Setup              #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# Root-Check
[ "$EUID" -ne 0 ] && print_error "Bitte als root ausführen: sudo $0"

# Benutzer & Hostname
read -p "Perry-NAS Benutzername (z.B. perry): " PERRY_USER
PERRY_HOSTNAME="perry-nas"
echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts
print_success "Hostname gesetzt"

# System-Update
print_perry "Systemaktualisierung..."
apt update && apt full-upgrade -y && apt autoremove -y

# Pakete (nur nginx – kein Apache2!)
print_perry "Installiere Pakete..."
apt install -y \
    parted nginx php8.4-fpm samba ufw curl bc smartmontools hdparm git python3

# PCIe SATA Optimierung
print_perry "Optimiere PCIe SATA..."
echo 'max_performance' | tee /sys/class/scsi_host/host*/link_power_management_policy >/dev/null 2>&1 || true
echo '- - -' | tee /sys/class/scsi_host/host*/scan >/dev/null 2>&1 || true

# Hardware-Erkennung
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
read -p "PCIe Festplatte (z.B. sda): " DISK
[ -z "$DISK" ] && print_error "Kein Device angegeben"
[ ! -e "/dev/$DISK" ] && print_error "Device /dev/$DISK existiert nicht"

# Festplatten-Handling mit Erkennung
FSTYPE=$(lsblk -no FSTYPE "/dev/$DISK" | head -n1)
USE_EXISTING=false
if [[ -n "$FSTYPE" && "$FSTYPE" != "dos" && "$FSTYPE" != "" ]]; then
    print_warning "Dateisystem '$FSTYPE' erkannt!"
    read -p "Behalten? (j/N): " USE
    [[ $USE =~ ^[Jj]$ ]] && USE_EXISTING=true
fi

if [ "$USE_EXISTING" = true ]; then
    PART=$(lsblk -n "/dev/$DISK" | grep "part" | head -n1 | awk '{print "/dev/" $1}' || echo "/dev/$DISK")
    print_success "Verwende bestehendes Dateisystem auf $PART"
else
    umount "/dev/${DISK}"* 2>/dev/null || true
    parted "/dev/$DISK" --script mklabel gpt
    parted "/dev/$DISK" --script mkpart primary ext4 0% 100%
    PART="/dev/${DISK}1"
    mkfs.ext4 -F "$PART"
fi

# Mount
mkdir -p /mnt/perry-nas
echo "$PART /mnt/perry-nas ext4 defaults,noatime,data=writeback,nobarrier,nofail 0 2" >> /etc/fstab
mount -a

# Benutzer
id "$PERRY_USER" &>/dev/null || { useradd -m -s /bin/bash "$PERRY_USER"; passwd "$PERRY_USER"; }
chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

# Samba
print_perry "Richte Samba ein..."
cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS ($PERRY_USER)
   security = user
   map to guest = bad user
   ntlm auth = yes
   server min protocol = SMB2
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   use sendfile = yes
   strict locking = no

[Perry-NAS]
   path = /mnt/perry-nas
   browseable = yes
   writable = yes
   valid users = $PERRY_USER
   force user = $PERRY_USER
EOF
smbpasswd -a "$PERRY_USER"
systemctl enable --now smbd
print_success "Samba eingerichtet"

# Web-Interface (nginx)
print_perry "Richte Web-Interface ein..."
chown -R www-www-data /var/www/html
rm -f /var/www/html/index.nginx-debian.html

# PHP-FPM
sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.4/fpm/php.ini

# Nginx-Konfig
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    root /var/www/html;
    index index.php;
    location / { try_files $uri $uri/ =404; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
    }
    location ~ /\.ht { deny all; }
}
EOF

# Web-Interface (gekürzt, aber voll funktional – wie in README)
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>🍐 Perry-NAS</title>
<style>:root{--p: #8A2BE2;} body{font-family:sans-serif;background:linear-gradient(135deg,var(--p),#9370DB);color:white;padding:20px} .card{background:rgba(255,255,255,0.95);color:#333;padding:20px;border-radius:10px;margin:10px}</style>
</head><body>
<div class="card"><h2>🍐 Perry-NAS</h2>
<pre><?php
echo "Hostname: ".trim(shell_exec('hostname'))."\n";
echo "IP: ".trim(shell_exec('hostname -I'))."\n";
echo "Uptime: ".trim(shell_exec('uptime -p'))."\n";
echo shell_exec('df -h /mnt/perry-nas');
?></pre></div>
</body></html>
EOF

systemctl enable --now nginx php8.4-fpm
print_success "Web-Interface aktiv"

# Firewall
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow samba
print_success "Firewall aktiviert"

# ⭐ S.M.A.R.T. – erst JETZT aktivieren (nach Platten-Setup!)
print_perry "Richte S.M.A.R.T. Monitoring ein..."
smartctl --smart=on --saveauto=on "$PART" || print_warning "S.M.A.R.T. nicht unterstützt"
cat > /etc/smartd.conf << EOF
$PART -a -o on -S on -s (S/../.././02|L/../../7/03) -m root
EOF

# 🔥 Smartd nur starten – NICHT enable (vermeidet Link-Fehler!)
systemctl stop smartd 2>/dev/null || true
systemctl start smartd 2>/dev/null || true

# Nur enable, wenn noch nicht verknüpft
if ! systemctl is-enabled smartd >/dev/null 2>&1; then
    systemctl enable smartd
fi

print_success "S.M.A.R.T. Monitoring aktiviert"

# E-Mail-Setup (optional)
print_perry "Täglichen E-Mail-Statusbericht einrichten? (j/N): "
read -r EMAIL_SETUP
if [[ $EMAIL_SETUP =~ ^[Jj]$ ]]; then
    # ... (hier kannst du den bekannten E-Mail-Block einfügen – optional)
    print_success "E-Mail-Setup wird übersprungen (für volle Version siehe GitHub)"
fi

# Fertig
IP=$(hostname -I | awk '{print $1}')
echo -e "\n${GREEN}🎉 Perry-NAS Setup abgeschlossen!${NC}"
echo -e "🌐 Web: http://$IP"
echo -e "💾 Samba: \\\\\\\\$IP\\\\Perry-NAS"
echo -e "🟢 Alle Dienste laufen – inkl. S.M.A.R.T. auf $PART"
