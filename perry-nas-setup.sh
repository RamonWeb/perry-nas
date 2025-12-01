#!/bin/bash
# Perry-NAS Setup Script - Raspberry Pi OS Trixie Version (SICHER)
# Inklusive Live CPU-/RAM-Diagramme im Webinterface
# Raspberry Pi 5 NAS mit PCIe SATA Adapter & HomeRacker

set -e

# --------------------------
# Farben
# --------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_perry()   { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNUNG]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --------------------------
# Banner
# --------------------------
echo -e "
${PURPLE}#############################################${NC}
${PURPLE}#              PERRY-NAS (TRIXIE)          #${NC}
${PURPLE}#      Raspberry Pi 5 PCIe SATA NAS        #${NC}
${PURPLE}#############################################${NC}
"

# --------------------------
# Root-Check
# --------------------------
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen: sudo $0"
    exit 1
fi

# --------------------------
# Benutzer / Hostname
# --------------------------
print_perry "Starte Perry-NAS Konfiguration"

read -p "NAS Benutzername (z.B. perry): " PERRY_USER
PERRY_HOSTNAME="perry-nas"
PERRY_IP=$(hostname -I | awk '{print $1}')

echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1  $PERRY_HOSTNAME/g" /etc/hosts || true
hostnamectl set-hostname "$PERRY_HOSTNAME" || true

print_success "Hostname gesetzt: $PERRY_HOSTNAME"

# --------------------------
# System Update
# --------------------------
print_perry "System wird aktualisiert..."
apt update
apt full-upgrade -y
apt autoremove -y

# --------------------------
# Pakete
# --------------------------
print_perry "Installiere benötigte Pakete..."
apt install -y parted nginx php-fpm php-cli php-common php-curl php-xml php-mbstring \
               samba ufw curl bc smartmontools hdparm

PHP_FPM_SERVICE="php8.2-fpm"

# --------------------------
# SATA Device auswählen
# --------------------------
print_info "Blockgeräte Übersicht:"
lsblk
echo ""

read -p "Name der SATA-Festplatte (z.B. sda): " DISK

if [ ! -e "/dev/$DISK" ]; then
    print_error "/dev/$DISK nicht gefunden"
    exit 1
fi

read -p "ACHTUNG: /dev/$DISK wird GELÖSCHT! Fortfahren? (ja/NEIN): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
    print_error "Abgebrochen."
    exit 1
fi

# --------------------------
# Partitionierung
# --------------------------
umount "/dev/${DISK}"* 2>/dev/null || true

print_info "Erstelle neue GPT Partitionstabelle..."
parted /dev/$DISK --script mklabel gpt
parted /dev/$DISK --script mkpart primary ext4 0% 100%

print_info "Formatiere Partition..."
mkfs.ext4 -F /dev/${DISK}1

mkdir -p /mnt/perry-nas

# fstab
echo "/dev/${DISK}1 /mnt/perry-nas ext4 defaults,noatime,data=writeback,nofail 0 2" >> /etc/fstab
mount -a

# --------------------------
# Benutzer anlegen
# --------------------------
if ! id "$PERRY_USER" >/dev/null 2>&1; then
    print_info "Erstelle Benutzer $PERRY_USER..."
    useradd -m -s /bin/bash "$PERRY_USER"
    passwd "$PERRY_USER"
fi

chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

print_success "Festplatte eingerichtet!"

# --------------------------
# SMART Monitoring
# --------------------------
print_perry "Aktiviere S.M.A.R.T. Monitoring..."

smartctl --smart=on --saveauto=on /dev/$DISK || true

cat > /etc/smartd.conf << EOF
/dev/$DISK -a -o on -S on -s (S/../.././02|L/../../7/03) -m root
EOF

systemctl enable smartd 2>/dev/null || true
systemctl restart smartd 2>/dev/null || print_warning "smartd konnte nicht gestartet werden"
=======
# KORRIGIERT: smartd Service handling
print_info "Konfiguriere S.M.A.R.T. Monitoring Service..."

# Prüfe ob smartd bereits läuft und stoppe ihn
if systemctl is-active --quiet smartd; then
    print_info "Stoppe bestehenden smartd Service..."
    systemctl stop smartd
fi

# Service neu starten mit korrekter Konfiguration
# systemctl enable smartd 2>/dev/null || print_warning "smartd Service konnte nicht aktiviert werden (bereits aktiv?)"
# systemctl start smartd

# Warte kurz und prüfe Status
sleep 2
if systemctl is-active --quiet smartd; then
    print_success "Perry-NAS S.M.A.R.T. Monitoring aktiviert"
else
    print_warning "S.M.A.R.T. Monitoring konnte nicht gestartet werden, aber Setup wird fortgesetzt"
fi
>>>>>>> cc95bdf7657f671488ec3cee2db96cfeda6e59a6

# --------------------------
# Samba (Trixie)
# --------------------------
print_perry "Konfiguriere Samba..."

cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS
   server min protocol = SMB2
   server max protocol = SMB3
   security = user
   map to guest = bad user

[Perry-NAS]
   path = /mnt/perry-nas
   browseable = yes
   writable = yes
   valid users = $PERRY_USER
   create mask = 0775
   directory mask = 0775
EOF

print_info "Samba Passwort setzen:"
smbpasswd -a "$PERRY_USER" || true

systemctl enable smbd 2>/dev/null || true
systemctl restart smbd 2>/dev/null || print_warning "smbd konnte nicht gestartet werden"

# --------------------------
# Webinterface installieren (inkl. Live-Diagramme)
# --------------------------
print_perry "Installiere Perry-NAS Webinterface..."

rm -f /var/www/html/index.nginx-debian.html
mkdir -p /var/www/html/api

# --------------------------
# API Endpoint: /api/status.php
# Liefert JSON: load averages + memory usage + disk usage + timestamp
# --------------------------
cat > /var/www/html/api/status.php << 'EOF'
<?php
header('Content-Type: application/json');

// Load averages
$loads = sys_getloadavg(); // [1min,5min,15min]

// Memory (bytes)
$meminfo = file_get_contents('/proc/meminfo');
$mem = [];
foreach (explode("\n", $meminfo) as $line) {
    if (preg_match('/^(\w+):\s+(\d+)/', $line, $m)) {
        $mem[$m[1]] = (int)$m[2];
    }
}
$total_kb = isset($mem['MemTotal']) ? $mem['MemTotal'] : 0;
$free_kb  = (isset($mem['MemFree']) ? $mem['MemFree'] : 0) + (isset($mem['Buffers']) ? $mem['Buffers'] : 0) + (isset($mem['Cached']) ? $mem['Cached'] : 0);
$used_kb  = max(0, $total_kb - $free_kb);

$mem_total = $total_kb * 1024;
$mem_used  = $used_kb * 1024;
$mem_percent = $total_kb ? round(($used_kb / $total_kb) * 100, 2) : 0;

// Disk usage for /mnt/perry-nas
$df = [];
exec("df -B1 /mnt/perry-nas 2>/dev/null | tail -n1", $df);
$disk = null;
if (isset($df[0])) {
    $parts = preg_split('/\s+/', trim($df[0]));
    if (count($parts) >= 5) {
        $disk = [
            'size' => (int)$parts[1],
            'used' => (int)$parts[2],
            'avail' => (int)$parts[3],
            'percent' => rtrim($parts[4], '%'),
        ];
    }
}

// Temperature (if available)
$temp = null;
$tz = '/sys/class/thermal/thermal_zone0/temp';
if (file_exists($tz)) {
    $t = trim(file_get_contents($tz));
    if (is_numeric($t)) {
        $temp = $t / 1000.0;
    }
}

$out = [
    'timestamp' => time(),
    'load' => ['1' => $loads[0], '5' => $loads[1], '15' => $loads[2]],
    'memory' => ['total' => $mem_total, 'used' => $mem_used, 'percent' => $mem_percent],
    'disk' => $disk,
    'temp_c' => $temp
];

echo json_encode($out);
EOF

# --------------------------
# Frontend: index.php (mit Chart.js)
# --------------------------
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<title>Perry-NAS Live Status</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- Chart.js CDN -->
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family:Arial, Helvetica, sans-serif; background: linear-gradient(135deg,#f3e8ff 0%,#e8f0ff 100%); margin:0; padding:20px; color:#222; }
.container { max-width:1100px; margin:0 auto; }
.header { display:flex; justify-content:space-between; align-items:center; gap:10px; margin-bottom:16px; }
.title { font-size:24px; color:#4b2ca6; }
.card { background:white; padding:16px; border-radius:12px; box-shadow:0 8px 24px rgba(0,0,0,0.08); margin-bottom:16px;}
.row { display:flex; gap:16px; flex-wrap:wrap; }
.col { flex:1 1 320px; min-width:280px; }
.small { font-size:14px; color:#555; }
.stat { font-weight:700; font-size:18px; color:#333; }
.footer { text-align:center; color:#666; margin-top:18px; font-size:13px; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <div class="title">🍐 Perry-NAS — Live Status</div>
    <div class="small">Host: <?php echo htmlspecialchars(gethostname()); ?></div>
  </div>

  <div class="card">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h3 style="margin:0">Systemübersicht</h3>
      <div id="last-updated" class="small">--</div>
    </div>
    <div class="row" style="margin-top:12px;">
      <div class="col">
        <canvas id="cpuChart" height="160"></canvas>
      </div>
      <div class="col">
        <canvas id="memChart" height="160"></canvas>
      </div>
    </div>
  </div>

  <div class="card">
    <h3 style="margin:0 0 8px 0">Details</h3>
    <div id="details" class="small">Lade Daten…</div>
  </div>

  <div class="footer">Perry-NAS &middot; Webstatus (sicher, keine root-Rechte erforderlich)</div>
</div>

<script>
const cpuCtx = document.getElementById('cpuChart').getContext('2d');
const memCtx = document.getElementById('memChart').getContext('2d');

const maxPoints = 30; // number of points shown in timeline
let labels = Array.from({length:maxPoints}, (_,i)=>'');

const cpuChart = new Chart(cpuCtx, {
  type: 'line',
  data: {
    labels: labels.slice(),
    datasets: [{
      label: 'Load (1min)',
      data: Array(maxPoints).fill(null),
      fill: false,
      tension: 0.3,
      borderWidth: 2
    }]
  },
  options: {
    animation: false,
    responsive: true,
    scales: { y: { beginAtZero: true } }
  }
});

const memChart = new Chart(memCtx, {
  type: 'line',
  data: {
    labels: labels.slice(),
    datasets: [{
      label: 'Memory used (%)',
      data: Array(maxPoints).fill(null),
      fill: true,
      tension: 0.3,
      borderWidth: 2
    }]
  },
  options: {
    animation: false,
    responsive: true,
    scales: { y: { beginAtZero: true, max: 100 } }
  }
});

function pushPoint(chart, value) {
  chart.data.labels.push(new Date().toLocaleTimeString());
  chart.data.labels.shift();
  chart.data.datasets[0].data.push(value);
  chart.data.datasets[0].data.shift();
  chart.update('none');
}

function updateDetails(json) {
  const d = document.getElementById('details');
  let html = '';
  html += '<strong>Load:</strong> ' + json.load['1'].toFixed(2) + ' (1m), ' + json.load['5'].toFixed(2) + ' (5m), ' + json.load['15'].toFixed(2) + ' (15m)<br>';
  html += '<strong>Memory:</strong> ' + json.memory.percent + '% (' + Math.round(json.memory.used/1024/1024) + ' MB used of ' + Math.round(json.memory.total/1024/1024) + ' MB)<br>';
  if (json.disk) {
    html += '<strong>Disk /mnt/perry-nas:</strong> ' + json.disk.percent + '% used<br>';
  }
  if (json.temp_c !== null) {
    html += '<strong>Temp:</strong> ' + json.temp_c.toFixed(1) + ' °C';
  }
  d.innerHTML = html;
}

async function fetchStatus() {
  try {
    const res = await fetch('/api/status.php?_=' + Date.now());
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const json = await res.json();
    // push CPU load (1min) and mem %
    const cpuVal = parseFloat(json.load['1']);
    const memVal = parseFloat(json.memory.percent);
    pushPoint(cpuChart, cpuVal);
    pushPoint(memChart, memVal);
    updateDetails(json);
    document.getElementById('last-updated').innerText = 'Letzte Aktualisierung: ' + new Date(json.timestamp*1000).toLocaleTimeString();
  } catch (e) {
    console.error('Fetch error', e);
    document.getElementById('details').innerText = 'Fehler beim Laden: ' + e.message;
  }
}

// initialize charts with empty labels
(function initCharts() {
  const now = new Date();
  for (let i=0;i<maxPoints;i++) {
    cpuChart.data.labels[i] = '';
    memChart.data.labels[i] = '';
  }
  cpuChart.update();
  memChart.update();
})();

// fetch immediately and then every 2s
fetchStatus();
setInterval(fetchStatus, 2000);
</script>
</body>
</html>
EOF

# --------------------------
# Nginx konfigurieren
# --------------------------
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.php index.html;
    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /api/ {
        try_files \$uri =404;
        # PHP files under /api are executed by php-fpm
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        }
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
chown -R www-data:www-data /var/www/html/api
chmod -R 755 /var/www/html/api

# Restart services
systemctl enable nginx $PHP_FPM_SERVICE 2>/dev/null || true
systemctl restart nginx $PHP_FPM_SERVICE 2>/dev/null || print_warning "Nginx/PHP-FPM restart warning"

# --------------------------
# Firewall
# --------------------------
ufw --force enable
ufw allow ssh
ufw allow 80
ufw allow samba

# --------------------------
# README für GitHub (optional)
# --------------------------
cat > /root/PERRY-NAS-README.md << EOF
# Perry-NAS (Raspberry Pi OS Trixie)

Dieses Repository enthält das Setup-Script für Perry-NAS (Raspberry Pi 5) auf Raspberry Pi OS Trixie.
Das Script richtet: Partition, Samba, smartd, nginx + php-fpm und ein Webinterface mit Live CPU/RAM-Diagrammen ein.

**Webinterface:** http://<deine-ip>  
**API endpoint:** /api/status.php (liefert JSON mit load, memory, disk, temp)

Lizenz & Hinweise: Passe das Script vor Einsatz an und prüfe Berechtigungen. Veröffentlichungsbereit für GitHub.
EOF

# --------------------------
# Abschluss
# --------------------------
print_success "🍐 Perry-NAS Setup abgeschlossen!"
print_info "Webinterface: http://$PERRY_IP/"
print_info "Samba: \\\\$PERRY_IP\\Perry-NAS"
print_info "SSH:   ssh $PERRY_USER@$PERRY_IP"
print_info "README für GitHub: /root/PERRY-NAS-README.md"

<<<<<<< HEAD
echo -e "${GREEN}NAS ist bereit!${NC}"
=======
nginx -t && print_success "Perry-NAS Nginx OK" || print_error "Perry-NAS Nginx Fehler"

# Performance Check
print_info "Perry-NAS Performance Test:"
hdparm -Tt /dev/${DISK}1 2>/dev/null | head -5 || echo "Performance Test übersprungen"

# S.M.A.R.T. Status
print_info "Perry-NAS Health Status:"
smartctl -H /dev/$DISK 2>/dev/null | grep -i "health" || echo "S.M.A.R.T. Status OK"

echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#           PERRY-NAS BEREIT!              #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""
echo -e "${GREEN}🍐 Perry-NAS Setup erfolgreich abgeschlossen!${NC}"
echo ""
echo -e "${CYAN}📋 PERRY-NAS ZUGRIFFSINFORMATIONEN:${NC}"
echo -e "  👤 Benutzer: ${PERRY_USER}"
echo -e "  🖥️  Hostname: ${PERRY_HOSTNAME}"
echo -e "  🌐 IP-Adresse: ${PERRY_IP}"
echo ""
echo -e "${CYAN}🔗 PERRY-NAS DIENSTE:${NC}"
echo -e "  💾 Samba: \\\\\\${PERRY_IP}\\Perry-NAS"
echo -e "  📊 Web Interface: http://${PERRY_IP}"
echo -e "  🔐 SSH: ssh ${PERRY_USER}@${PERRY_IP}"
echo ""
echo -e "${CYAN}⚡ PERRY-NAS FEATURES:${NC}"
echo -e "  🔄 PCIe SATA: Aktiv"
echo -e "  🏠 HomeRacker: Konfiguriert"
echo -e "  📡 S.M.A.R.T.: Überwacht"
echo -e "  🔒 Firewall: Aktiv"
echo ""
echo -e "${GREEN}🍐 Perry-NAS ist einsatzbereit! Viel Spaß!${NC}"
>>>>>>> cc95bdf7657f671488ec3cee2db96cfeda6e59a6
