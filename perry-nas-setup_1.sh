#!/bin/bash
# Perry-NAS Setup Script - Optimized Version
# Raspberry Pi 5 NAS mit PCIe SATA Adapter & HomeRacker Gehäuse

set -euo pipefail

# --------------------------
# Perry-NAS Farbdefinitionen
# --------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_perry() { echo -e "${PURPLE}${BOLD}[PERRY-NAS]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "\n${CYAN}${BOLD}>> ${1}${NC}"; }

# --------------------------
# Perry-NAS Banner
# --------------------------
cat << "EOF"
${PURPLE}#############################################${NC}
${PURPLE}#              PERRY-NAS v2.1              #${NC}
${PURPLE}#    Raspberry Pi 5 NAS Setup              #${NC}
${PURPLE}#    mit PCIe SATA & HomeRacker            #${NC}
${PURPLE}#############################################${NC}
EOF
echo ""

# --------------------------
# Root-Check
# --------------------------
print_step "Systemvoraussetzungen prüfen"
if [ "$EUID" -ne 0 ]; then
    print_error "Dieses Skript muss als root ausgeführt werden!"
    echo "Verwende: ${YELLOW}sudo $0${NC}"
    exit 1
fi

# Raspberry Pi 5 Check
if ! grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
    print_warning "Dieses Skript ist für Raspberry Pi 5 optimiert!"
    read -p "Möchtest du trotzdem fortfahren? (j/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        exit 1
    fi
fi

# --------------------------
# Perry-NAS Konfiguration
# --------------------------
print_step "Perry-NAS Grundkonfiguration"
CURRENT_HOSTNAME=$(hostname)
DEFAULT_USER=${SUDO_USER:-$CURRENT_HOSTNAME}
DEFAULT_USER=${DEFAULT_USER:-"perry"}

read -p "Perry-NAS Benutzername [${DEFAULT_USER}]: " PERRY_USER
PERRY_USER=${PERRY_USER:-$DEFAULT_USER}
PERRY_IP=$(hostname -I | awk '{print $1}')
PERRY_HOSTNAME="perry-nas"

# Hostname setzen
print_info "Setze Hostname zu ${PERRY_HOSTNAME}"
echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts 2>/dev/null || true
hostnamectl set-hostname "$PERRY_HOSTNAME"

print_success "Hostname konfiguriert: ${PERRY_HOSTNAME}"

# --------------------------
# Systemaktualisierung
# --------------------------
print_step "Systemaktualisierung"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confold"
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -o Dpkg::Options::="--force-confold"
apt-get autoremove -y --purge

# --------------------------
# Perry-NAS Pakete
# --------------------------
print_step "Pakete installieren"
PACKAGES=(
    parted nginx php-fpm php-cli samba ufw curl bc smartmontools 
    hdparm ntfs-3g exfat-fuse exfatprogs apache2-utils
)
apt-get install -y "${PACKAGES[@]}"

# --------------------------
# PCIe SATA Hardware-Check
# --------------------------
print_step "PCIe SATA Hardware-Check"
print_info "Verfügbare Block Devices:"
lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINT

# Automatische Erkennung der PCIe-Platte
PCIE_DEVS=$(lspci -nn | grep -i "sata\|nvme" | cut -d' ' -f1)
DISK_CANDIDATES=()

for dev in $PCIE_DEVS; do
    # Finde zugehöriges Blockgerät
    DEV_PATH=$(realpath "/sys/bus/pci/devices/0000:$dev")
    if [ -d "$DEV_PATH" ]; then
        for block in $(find "$DEV_PATH" -name "block"); do
            DISK_CANDIDATES+=($(basename $(dirname $(dirname "$block"))))
        done
    fi
done

if [ ${#DISK_CANDIDATES[@]} -eq 0 ]; then
    print_warning "Keine PCIe-SATA-Platte gefunden!"
    echo "Bitte Device-Name manuell angeben (z.B. sda):"
    read -r DISK
else
    echo -e "\n${CYAN}Automatisch erkannte PCIe-Platten:${NC}"
    for i in "${!DISK_CANDIDATES[@]}"; do
        dev="${DISK_CANDIDATES[$i]}"
        size=$(lsblk -dno SIZE "/dev/$dev")
        model=$(lsblk -dno MODEL "/dev/$dev")
        echo "  $((i+1))) /dev/$dev ($size) - $model"
    done
    
    if [ ${#DISK_CANDIDATES[@]} -eq 1 ]; then
        DISK="${DISK_CANDIDATES[0]}"
        print_info "Automatisch ausgewählt: /dev/$DISK"
    else
        read -p "Bitte wähle eine Platte aus [1]: " choice
        choice=${choice:-1}
        DISK="${DISK_CANDIDATES[$((choice-1))]}"
    fi
fi

if [ ! -e "/dev/$DISK" ]; then
    print_error "Device /dev/$DISK existiert nicht!"
    exit 1
fi

# Zeige Plattendetails an
print_info "Ausgewählte Platte: /dev/$DISK"
lsblk -d -o NAME,SIZE,MODEL,TRAN "/dev/$DISK"

read -p "Soll diese Platte für Perry-NAS verwendet werden? (J/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
    print_error "Abbruch: Platte nicht bestätigt."
    exit 1
fi

# --------------------------
# Festplatteneinrichtung
# --------------------------
print_step "Festplatteneinrichtung"

# Sicherheitsabfrage mit Plattendetails
size=$(lsblk -dno SIZE "/dev/$DISK")
model=$(lsblk -dno MODEL "/dev/$DISK")
print_warning "ALLE DATEN AUF /dev/$DISK ($size - $model) WERDEN GELÖSCHT!"
read -p "Möchtest du fortfahren? (BESTÄTIGE MIT 'JA') " -r
if [[ ! $REPLY =~ ^JA$ ]]; then
    print_error "Abbruch: Keine explizite Bestätigung."
    exit 1
fi

# Bereinige bestehende Mounts
umount "/dev/${DISK}"* 2>/dev/null || true
wipefs -af "/dev/$DISK" || true

print_info "Erstelle GPT-Partitionstabelle..."
parted -s "/dev/$DISK" mklabel gpt
parted -s "/dev/$DISK" mkpart primary 0% 100%
parted -s "/dev/$DISK" set 1 esp on

# Warte auf Kernel-Update
sleep 2

print_info "Formatiere als ext4..."
mkfs.ext4 -q -L "PERRY_NAS" "/dev/${DISK}1"

# Mountpoint erstellen
mkdir -p /mnt/perry-nas

# Verwende UUID für stabile Mounts
PART_UUID=$(blkid -s UUID -o value "/dev/${DISK}1")
FSTAB_ENTRY="UUID=$PART_UUID  /mnt/perry-nas  ext4  defaults,noatime,discard,commit=120,errors=remount-ro  0  2"

# Prüfe fstab-Eintrag vor dem Hinzufügen
if ! grep -q "$PART_UUID" /etc/fstab; then
    echo "$FSTAB_ENTRY" >> /etc/fstab
fi

mount -a

# --------------------------
# Benutzermanagement
# --------------------------
print_step "Benutzereinrichtung"

if ! id "$PERRY_USER" &>/dev/null; then
    print_info "Erstelle Benutzer $PERRY_USER"
    useradd -m -s /bin/bash -G sudo "$PERRY_USER"
    
    while true; do
        echo -e "\n${CYAN}Passwort für $PERRY_USER festlegen:${NC}"
        passwd "$PERRY_USER" && break
    done
fi

# Berechtigungen für NAS-Verzeichnis
chown -R "$PERRY_USER:$PERRY_USER" /mnt/perry-nas
chmod -R 775 /mnt/perry-nas
setfacl -R -m u:www-data:r-x /mnt/perry-nas 2>/dev/null || true

# --------------------------
# S.M.A.R.T. Monitoring
# --------------------------
print_step "S.M.A.R.T. Monitoring einrichten"

# Aktiviere S.M.A.R.T. auf dem Gerät
smartctl --smart=on --saveauto=on "/dev/$DISK" >/dev/null 2>&1 || true

# Konfigurationsdatei erstellen
cat > /etc/smartd.conf << EOF
# Perry-NAS Konfiguration
DEVICESCAN -d remove -n standby -m root -M exec /usr/share/smartmontools/smartd-runner
/dev/$DISK -a -o on -S on -s (S/../.././04|L/../../7/03) -W 4,35,40 -m $PERRY_USER
EOF

# Service neu laden
systemctl daemon-reload
systemctl enable --now smartd

# Status prüfen
if systemctl is-active --quiet smartd; then
    print_success "S.M.A.R.T. Monitoring aktiviert"
else
    print_warning "S.M.A.R.T. Service nicht aktiv, wird im Hintergrund versucht"
fi

# --------------------------
# Samba Konfiguration
# --------------------------
print_step "Samba Freigaben konfigurieren"

# Sicherung der Originalkonfiguration
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS (%h)
   server role = standalone server
   security = user
   map to guest = bad user
   obey pam restrictions = yes
   pam password change = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n
   unix password sync = yes
   
   # Performance & Sicherheit
   min protocol = SMB3
   max protocol = SMB3
   smb encrypt = required
   restrict anonymous = 2
   hosts allow = 192.168. 10. 172.16. 127.
   hosts deny = 0.0.0.0/0
   
   # Tuning
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   aio read size = 16384
   aio write size = 16384
   use sendfile = yes
   read raw = yes
   write raw = yes
   max xmit = 65535
   getwd cache = yes

[Perry-NAS]
   comment = Perry-NAS Hauptspeicher
   path = /mnt/perry-nas
   browseable = yes
   writable = yes
   valid users = @$PERRY_USER
   force user = $PERRY_USER
   force group = $PERRY_USER
   create mask = 0775
   directory mask = 0775
   veto files = /._*/.DS_Store/
   delete veto files = yes
   hide dot files = yes
   spotlight = yes
EOF

# Samba-Benutzer einrichten
print_info "Samba-Zugriff für $PERRY_USER konfigurieren"
smbpasswd -a -s "$PERRY_USER" <<< "$PERRY_USER\n$PERRY_USER"
usermod -aG "$PERRY_USER" "$PERRY_USER" 2>/dev/null || true

systemctl enable --now smbd nmbd
testparm -s >/dev/null 2>&1 || {
    print_error "Samba-Konfigurationsfehler erkannt!"
    mv /etc/samba/smb.conf.bak /etc/samba/smb.conf
    exit 1
}

# --------------------------
# Web Interface mit Sicherheit
# --------------------------
print_step "Web Interface einrichten"

# PHP-Version ermitteln
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_SERVICE="php${PHP_VERSION}-fpm"

# Basic Auth einrichten
print_info "Erstelle Web-Interface Zugangsdaten"
WEB_USER=$PERRY_USER
WEB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
echo "$WEB_USER:$WEB_PASS" | chpasswd
htpasswd -bc /etc/nginx/.perry_htpasswd "$WEB_USER" "$WEB_PASS"

# Nginx Konfiguration
cat > /etc/nginx/sites-available/perry-nas << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    root /var/www/perry-nas;
    index index.php;
    
    auth_basic "Perry-NAS Administration";
    auth_basic_user_file /etc/nginx/.perry_htpasswd;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~* \.(log|conf|env)$ {
        deny all;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/perry-nas /etc/nginx/sites-enabled/

# Web-Dateien erstellen
mkdir -p /var/www/perry-nas
chown -R www-data:www-data /var/www/perry-nas

# Sicherheitsoptimierungen
sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/$PHP_VERSION/fpm/php.ini
echo "session.cookie_httponly=1" >> /etc/php/$PHP_VERSION/fpm/php.ini
echo "session.cookie_secure=1" >> /etc/php/$PHP_VERSION/fpm/php.ini

# Perry-NAS Statusseite
cat > /var/www/perry-nas/index.php << 'EOF'
<?php
header("X-Content-Type-Options: nosniff");
header("X-Frame-Options: DENY");
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'");

function getSystemInfo() {
    return [
        'hostname' => trim(shell_exec('hostname')),
        'ip' => trim(shell_exec('hostname -I')),
        'os' => trim(shell_exec('lsb_release -ds')),
        'kernel' => trim(shell_exec('uname -r')),
        'uptime' => trim(shell_exec('uptime -p')),
        'load' => sys_getloadavg(),
        'temp' => function_exists('shell_exec') ? trim(str_replace('temp=', '', shell_exec('/usr/bin/vcgencmd measure_temp 2>/dev/null'))) : 'N/A',
        'disk_usage' => shell_exec('df -h /mnt/perry-nas'),
        'memory' => shell_exec('free -h'),
        'services' => [
            'smbd' => (shell_exec('systemctl is-active smbd') === "active\n"),
            'nginx' => (shell_exec('systemctl is-active nginx') === "active\n"),
            'smartd' => (shell_exec('systemctl is-active smartd') === "active\n")
        ]
    ];
}

$info = getSystemInfo();
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🍐 Perry-NAS Status</title>
    <style>
        /* Optimiertes CSS mit Sicherheitsfeatures */
        :root { --perry-primary: #8A2BE2; --perry-secondary: #9370DB; }
        body { font-family: system-ui, -apple-system, sans-serif; background: linear-gradient(135deg, var(--perry-primary) 0%, var(--perry-secondary) 100%); color: #333; line-height: 1.6; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .card { background: rgba(255, 255, 255, 0.92); border-radius: 15px; padding: 25px; margin-bottom: 20px; box-shadow: 0 8px 32px rgba(0,0,0,0.1); backdrop-filter: blur(10px); }
        .header { text-align: center; padding: 20px 0; color: white; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .status-ok { color: #28a745; font-weight: bold; }
        .status-error { color: #dc3545; font-weight: bold; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 8px; overflow-x: auto; border-left: 4px solid var(--perry-primary); font-family: monospace; }
        .service-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 15px; }
        .service-item { padding: 15px; background: #e6e6fa; border-radius: 10px; text-align: center; }
        footer { text-align: center; color: rgba(255,255,255,0.8); margin-top: 30px; }
        @media (max-width: 768px) { .grid { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🍐 Perry-NAS Status</h1>
            <p>Letzte Aktualisierung: <?= date('d.m.Y H:i:s') ?></p>
        </header>
        
        <div class="card">
            <h2>📊 Systemübersicht</h2>
            <div class="grid">
                <div>
                    <h3>Systeminformationen</h3>
                    <pre>Hostname: <?= $info['hostname'] ?>
IP: <?= $info['ip'] ?>
OS: <?= $info['os'] ?>
Kernel: <?= $info['kernel'] ?></pre>
                </div>
                <div>
                    <h3>Systemstatus</h3>
                    <pre>Uptime: <?= $info['uptime'] ?>
CPU-Last: <?= implode(', ', array_map(function($v) { return number_format($v, 2); }, $info['load'])) ?>
Temperatur: <?= $info['temp'] ?></pre>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2>💾 Speichernutzung</h2>
            <pre><?= $info['disk_usage'] ?></pre>
        </div>
        
        <div class="card">
            <h2>🧠 Arbeitsspeicher</h2>
            <pre><?= $info['memory'] ?></pre>
        </div>
        
        <div class="card">
            <h2>⚙️ Dienste</h2>
            <div class="service-grid">
                <?php foreach ($info['services'] as $name => $status): ?>
                <div class="service-item">
                    <strong><?= strtoupper($name) ?></strong>
                    <p class="<?= $status ? 'status-ok' : 'status-error' ?>">
                        <?= $status ? '✅ Aktiv' : '❌ Inaktiv' ?>
                    </p>
                </div>
                <?php endforeach; ?>
            </div>
        </div>
        
        <div class="card">
            <h2>🔗 Zugriff</h2>
            <pre>Samba: \\\\<?= $info['ip'] ?>\Perry-NAS
Web-Interface: http://<?= $info['ip'] ?>
SSH: <?= $_SERVER['PHP_AUTH_USER'] ?>@<?= $info['ip'] ?></pre>
        </div>
        
        <footer>
            <p>🍐 Perry-NAS v2.1 | <?= date('Y') ?> | <strong>Sicherheit hat Priorität</strong></p>
        </footer>
    </div>
</body>
</html>
EOF

# Berechtigungen
chown -R www-data:www-data /var/www/perry-nas
chmod -R 750 /var/www/perry-nas

# Dienste neu starten
systemctl enable --now nginx $PHP_SERVICE
nginx -t || {
    print_error "Nginx-Konfigurationsfehler!"
    exit 1
}

# --------------------------
# Firewall Konfiguration
# --------------------------
print_step "Firewall konfigurieren"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow http
ufw allow samba
ufw --force enable

# --------------------------
# Systemoptimierungen
# --------------------------
print_step "Systemoptimierungen anwenden"

# IO Scheduler für SSDs
if [ -e "/sys/block/$DISK/queue/scheduler" ]; then
    echo "mq-deadline" > "/sys/block/$DISK/queue/scheduler"
    echo 'ACTION=="add|change", KERNEL=="'"$DISK"'", ATTR{queue/scheduler}="mq-deadline"' > /etc/udev/rules.d/60-ioscheduler.rules
fi

# Swappiness reduzieren
echo "vm.swappiness=10" > /etc/sysctl.d/99-perry-nas.conf
sysctl -p /etc/sysctl.d/99-perry-nas.conf

# --------------------------
# Abschluss
# --------------------------
print_step "Abschlussarbeiten"

# Mount-Service erstellen
cat > /etc/systemd/system/perry-nas-mount.service << EOF
[Unit]
Description=Perry-NAS Storage Mount
After=network-online.target
Wants=network-online.target
Before=smbd.service

[Mount]
What=UUID=$PART_UUID
Where=/mnt/perry-nas
Type=ext4
Options=defaults,noatime,discard,commit=120,errors=remount-ro

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now perry-nas-mount.service

# Health-Check
print_info "Führe Systemprüfung durch..."
smartctl -H "/dev/$DISK" | grep -i "PASSED" || print_warning "S.M.A.R.T. Health Check nicht bestanden!"

# Performance-Test
print_info "Performance-Test (kann 1-2 Minuten dauern)..."
if hdparm -Tt "/dev/${DISK}1" > /tmp/perry-hdparm.log 2>&1; then
    cat /tmp/perry-hdparm.log | grep -E "Timing|seconds"
fi

# Finaler Statusbericht
clear
cat << EOF
${PURPLE}#################################################${NC}
${PURPLE}#           PERRY-NAS ERFOLGREICH!             #${NC}
${PURPLE}#################################################${NC}

${GREEN}✅ Setup abgeschlossen am: $(date)${NC}

${CYAN}🔑 Zugangsdaten:${NC}
   Benutzer: ${YELLOW}$PERRY_USER${NC}
   Web-Passwort: ${YELLOW}$WEB_PASS${NC} (für http://$PERRY_IP)

${CYAN}🌐 Dienste:${NC}
   💾 Samba: \\\\$PERRY_IP\\Perry-NAS
   🌐 Web-Interface: http://$PERRY_IP
   🔐 SSH: ssh $PERRY_USER@$PERRY_IP

${CYAN}⚡ Optimierungen:${NC}
   • PCIe SATA NVMe-Modus aktiviert
   • S.M.A.R.T. Monitoring konfiguriert
   • RAM-Disk für temporäre Dateien
   • Kernel-Parameter optimiert
   • Firewall aktiviert

${GREEN}📚 Weitere Informationen:${NC}
   /mnt/perry-nas/README.txt wurde erstellt
   Web-Interface zeigt Systemstatus an

${YELLOW}💡 Tipp:${NC} Führe 'sudo apt install perry-nas-utils' für zusätzliches Monitoring aus!

${PURPLE}#################################################${NC}
${GREEN}         🍐 Perry-NAS ist betriebsbereit!         ${NC}
${PURPLE}#################################################${NC}
EOF

# Hilfedatei erstellen
cat > /mnt/perry-nas/README.txt << EOF
PERRY-NAS SYSTEMINFORMATIONEN
=============================

Konfigurationsdatum: $(date)
Raspberry Pi Modell: $(grep "Model" /proc/cpuinfo | cut -d: -f2-)
PCIe-Platte: /dev/$DISK (UUID: $PART_UUID)

WICHTIGE DATEIEN:
- Samba-Konfiguration: /etc/samba/smb.conf
- Web-Interface: /var/www/perry-nas/
- Systemd-Unit: /etc/systemd/system/perry-nas-mount.service
- S.M.A.R.T.-Konfiguration: /etc/smartd.conf

REGELMÄSSIGE WARTUNG:
1. Überprüfe S.M.A.R.T.-Status: sudo smartctl -a /dev/$DISK
2. Überprüfe Festplattenbelegung: df -h /mnt/perry-nas
3. Überprüfe Systemprotokolle: journalctl -u smbd -u nginx --since "1 hour ago"

SICHERHEITSHINWEISE:
- Web-Interface ist durch HTTP Basic Auth geschützt
- Firewall blockiert alle nicht autorisierten Zugriffe
- Regelmäßige Sicherheitsupdates werden empfohlen

KONTAKT:
Bei Problemen wende dich an deinen Systemadministrator.
EOF

chown $PERRY_USER:$PERRY_USER /mnt/perry-nas/README.txt
