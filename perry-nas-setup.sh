#!/bin/bash
# Perry-NAS Setup Script – Finale Version für Raspberry Pi 5
# HomeRacker • PCIe SATA • Debian Trixie • nginx only • Kein Apache2

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
echo -e "${PURPLE}#    Raspberry Pi 5 + HomeRacker + PCIe    #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# Root-Check
[ "$EUID" -ne 0 ] && print_error "Bitte als root ausführen: sudo $0"

# Benutzer einrichten
read -p "Perry-NAS Benutzername (z.B. perry): " PERRY_USER
PERRY_HOSTNAME="perry-nas"
echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts
print_success "Hostname gesetzt: $PERRY_HOSTNAME"

# System-Update
print_perry "Aktualisiere System..."
apt update && apt full-upgrade -y && apt autoremove -y

# Pakete installieren
print_perry "Installiere Perry-NAS Pakete..."
apt install -y \
    parted nginx php8.4-fpm samba ufw curl bc smartmontools hdparm git python3

# PCIe SATA Optimierung
print_perry "Optimiere PCIe SATA..."
echo 'max_performance' | tee /sys/class/scsi_host/host*/link_power_management_policy >/dev/null 2>&1 || true
echo '- - -' | tee /sys/class/scsi_host/host*/scan >/dev/null 2>&1 || true

# Festplatten-Erkennung
print_perry "Erkenne Festplatten..."
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
read -p "PCIe Festplatte (z.B. sda): " DISK
[ -z "$DISK" ] && print_error "Kein Device angegeben"
[ ! -e "/dev/$DISK" ] && print_error "Device /dev/$DISK existiert nicht"

# Bestehendes Dateisystem erkennen
FSTYPE=$(lsblk -no FSTYPE "/dev/$DISK" | head -n1)
USE_EXISTING=false
if [[ -n "$FSTYPE" && "$FSTYPE" != "dos" && "$FSTYPE" != "" ]]; then
    print_warning "Dateisystem '$FSTYPE' erkannt!"
    read -p "Behalten? (j/N): " USE
    [[ $USE =~ ^[Jj]$ ]] && USE_EXISTING=true
fi

# Partitionierung
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

# Mount einrichten
mkdir -p /mnt/perry-nas
echo "$PART /mnt/perry-nas ext4 defaults,noatime,data=writeback,nobarrier,nofail 0 2" >> /etc/fstab
mount -a
id "$PERRY_USER" &>/dev/null || { useradd -m -s /bin/bash "$PERRY_USER"; passwd "$PERRY_USER"; }
chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

# Samba einrichten
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
chown -R www-data:www-data /var/www/html  # ✅ Korrekt: www-data (nicht www-www-data)
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

# Perry-Themed Web-Interface (aus README)
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <title>🍐 Perry-NAS Status</title>
    <style>
        :root { --perry: #8A2BE2; }
        body { font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, var(--perry), #9370DB); color: white; padding: 20px; }
        .card { background: rgba(255,255,255,0.95); color: #333; padding: 20px; border-radius: 10px; margin: 15px 0; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="card">
        <h2>🍐 Perry-NAS</h2>
        <pre><?php
            echo "Hostname: " . trim(shell_exec('hostname')) . "\n";
            echo "IP: " . trim(shell_exec('hostname -I')) . "\n";
            echo "Uptime: " . trim(shell_exec('uptime -p')) . "\n";
            echo shell_exec('df -h /mnt/perry-nas');
        ?></pre>
    </div>
</body>
</html>
EOF

systemctl enable --now nginx php8.4-fpm
print_success "Web-Interface aktiviert"

# Firewall
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow samba
print_success "Firewall aktiviert"

# 🔥 S.M.A.R.T. – korrekt für Debian Trixie
print_perry "Richte S.M.A.R.T. Monitoring ein..."

# Sicherstellen, dass smartd.service existiert
if [ ! -f /lib/systemd/system/smartd.service ]; then
    if [ -f /usr/share/doc/smartmontools/smartd.service ]; then
        cp /usr/share/doc/smartmontools/smartd.service /lib/systemd/system/
    else
        tee /lib/systemd/system/smartd.service << 'EOF' >/dev/null
[Unit]
Description=SMART Disk Monitoring Daemon
After=local-fs.target
[Service]
Type=forking
ExecStart=/usr/sbin/smartd -d
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/smartd.pid
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl daemon-reload
fi

smartctl --smart=on --saveauto=on "$PART" || print_warning "S.M.A.R.T. nicht unterstützt"
cat > /etc/smartd.conf << EOF
$PART -a -o on -S on -s (S/../.././02|L/../../7/03)
EOF

systemctl stop smartd 2>/dev/null || true
systemctl start smartd
systemctl enable smartd
print_success "S.M.A.R.T. Monitoring aktiviert"

# Optional: E-Mail-Setup (kann später hinzugefügt werden)
print_perry "✅ Perry-NAS Setup abgeschlossen!"
IP=$(hostname -I | awk '{print $1}')
echo -e "\n${GREEN}🌐 Web-Interface: http://$IP${NC}"
echo -e "${GREEN}💾 Samba: \\\\\\\\$IP\\\\Perry-NAS${NC}"
echo -e "${GREEN}🐧 SSH: ssh $PERRY_USER@$IP${NC}"
echo -e "\n${PURPLE}🍐 Perry-NAS ist bereit – Dein zuverlässiger Speicherpartner!${NC}"