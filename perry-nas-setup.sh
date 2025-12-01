#!/bin/bash
# Perry-NAS Setup Script – Raspberry Pi OS TRIXIE Version
# Raspberry Pi 5 NAS mit PCIe SATA & HomeRacker

set -e

#############################################
# Farbdefinitionen
#############################################
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

#############################################
# Banner
#############################################
echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#              PERRY-NAS (Trixie)           #${NC}"
echo -e "${PURPLE}#       Raspberry Pi 5 PCIe NAS Setup       #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

#############################################
# Root-Check
#############################################
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte führe das Skript als root aus: sudo $0"
    exit 1
fi

#############################################
# Konfiguration
#############################################
print_perry "Perry-NAS Konfiguration"

read -p "Perry-NAS Benutzername eingeben (z.B. perry): " PERRY_USER
PERRY_IP=$(hostname -I | awk '{print $1}')
PERRY_HOSTNAME="perry-nas"

echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts

print_success "Hostname gesetzt: $PERRY_HOSTNAME"

#############################################
# Systemupdate
#############################################
print_perry "Systemaktualisierung..."
apt update
apt full-upgrade -y
apt autoremove -y

#############################################
# Paketinstallation
#############################################
print_perry "Installiere benötigte Pakete..."
apt install -y parted nginx php-fpm php-cli samba ufw curl bc smartmontools hdparm

#############################################
# PCIe SATA Hardware
#############################################
print_perry "PCIe SATA Geräteerkennung"

lsblk

read -p "Bitte Device Name der PCIe Festplatte eingeben (z.B. sda): " DISK

if [ ! -e "/dev/$DISK" ]; then
    print_error "Device /dev/$DISK existiert nicht!"
    exit 1
fi

read -p "ALLE DATEN AUF /dev/$DISK LÖSCHEN? (ja/NEIN): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
    print_error "Vorgang abgebrochen."
    exit 1
fi

#############################################
# Festplatte einrichten
#############################################
umount "/dev/$DISK"* 2>/dev/null || true

parted "/dev/$DISK" --script mklabel gpt
parted "/dev/$DISK" --script mkpart primary ext4 0% 100%

mkfs.ext4 -F "/dev/${DISK}1"

mkdir -p /mnt/perry-nas
echo "/dev/${DISK}1  /mnt/perry-nas  ext4  defaults,noatime,nofail  0  2" >> /etc/fstab

mount -a

#############################################
# Benutzer anlegen
#############################################
if ! id "$PERRY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$PERRY_USER"
    passwd "$PERRY_USER"
fi

chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

#############################################
# SMART Monitoring (Trixie)
#############################################
print_perry "Aktiviere S.M.A.R.T."

smartctl --smart=on --saveauto=on /dev/$DISK

cat > /etc/smartd.conf << EOF
/dev/$DISK -a -o on -S on -m root
EOF

systemctl restart smartd || print_warning "SMART konnte nicht gestartet werden"

#############################################
# Samba Konfiguration
#############################################
print_perry "Samba Konfiguration"

tee /etc/samba/smb.conf > /dev/null << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS ($PERRY_USER)
   server min protocol = SMB2
   server max protocol = SMB3
   security = user
   map to guest = bad user

[Perry-NAS]
   path = /mnt/perry-nas
   valid users = $PERRY_USER
   writable = yes
   browseable = yes
   create mask = 0775
   directory mask = 0775
EOF

smbpasswd -a "$PERRY_USER"
systemctl restart smbd

#############################################
# Webinterface installieren
#############################################
print_perry "Installiere Perry-NAS Webinterface…"

rm -f /var/www/html/index.nginx-debian.html

PHP_SOCKET="/var/run/php/php8.2-fpm.sock"

#############################################
# Nginx Config
#############################################
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    root /var/www/html;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:$PHP_SOCKET;
        include snippets/fastcgi-php.conf;
    }
}
EOF

#############################################
# API für Live-Daten
#############################################
mkdir -p /var/www/html/api

cat > /var/www/html/api/status.php << 'EOF'
<?php
header('Content-Type: application/json');

$loads = sys_getloadavg();

$meminfo = file('/proc/meminfo');
$mem = [];
foreach ($meminfo as $line) {
    if (preg_match('/^(\w+):\s+(\d+)/', $line, $m)) $mem[$m[1]] = (int)$m[2];
}
$total = $mem['MemTotal'] ?? 0;
$free  = ($mem['MemFree'] ?? 0) + ($mem['Buffers'] ?? 0) + ($mem['Cached'] ?? 0);
$used  = $total - $free;

$temp = null;
if (file_exists('/sys/class/thermal/thermal_zone0/temp')) {
    $t = trim(file_get_contents('/sys/class/thermal/thermal_zone0/temp'));
    if (is_numeric($t)) $temp = $t / 1000;
}

echo json_encode([
    "timestamp" => time(),
    "load" => $loads,
    "memory" => [
        "total" => $total * 1024,
        "used"  => $used  * 1024,
    ],
    "temp" => $temp
]);
EOF

#############################################
# Webinterface HTML
#############################################
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Perry-NAS Status</title>
<script>
async function update() {
    const r = await fetch('/api/status.php');
    const j = await r.json();

    document.getElementById("cpu").innerText = j.load[0].toFixed(2);
    document.getElementById("ram").innerText = 
        ((j.memory.used / j.memory.total) * 100).toFixed(1);

    if (j.temp)
        document.getElementById("temp").innerText = j.temp.toFixed(1);

    // Live Charts
    cpuChart.data.labels.push("");
    cpuChart.data.datasets[0].data.push(j.load[0]);
    cpuChart.update();

    ramChart.data.labels.push("");
    ramChart.data.datasets[0].data.push(
        (j.memory.used / j.memory.total) * 100
    );
    ramChart.update();
}
setInterval(update, 1500);
</script>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body style="font-family:sans-serif">
<h1>🍐 Perry-NAS Live Status</h1>

<p>CPU Load: <span id="cpu"></span></p>
<p>RAM Nutzung: <span id="ram"></span>%</p>
<p>Temperatur: <span id="temp"></span> °C</p>

<h2>CPU Verlauf</h2>
<canvas id="cpuChart"></canvas>

<h2>RAM Verlauf</h2>
<canvas id="ramChart"></canvas>

<script>
const cpuChart = new Chart(document.getElementById('cpuChart'), {
    type: 'line',
    data: { labels: [], datasets: [{ label: 'CPU Load', data: [] }] }
});
const ramChart = new Chart(document.getElementById('ramChart'), {
    type: 'line',
    data: { labels: [], datasets: [{ label: 'RAM %', data: [] }] }
});
</script>

</body>
</html>
EOF

#############################################
# Firewall
#############################################
ufw allow ssh
ufw allow 80
ufw allow samba
ufw --force enable

#############################################
# Autostart
#############################################
systemctl enable nginx
systemctl enable php8.2-fpm
systemctl enable smbd
systemctl enable smartd

#############################################
# Systemd Mount Fix
#############################################
cat > /etc/systemd/system/perry-nas-mount.service << EOF
[Unit]
Description=Perry-NAS Storage Mount
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/mount /mnt/perry-nas
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable perry-nas-mount.service

#############################################
# Abschluss
#############################################
print_success "🍐 Perry-NAS Setup erfolgreich abgeschlossen!"
echo "Webinterface: http://$PERRY_IP/"
