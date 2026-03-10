#!/bin/bash

# ==============================================================================
# PERRY-NAS: Pip-Boy Terminal & System Management Suite
# Autor: Ramon (via Gemini AI)
# System: Raspberry Pi 5 / Debian 13 (Trixie)
# Features: Web-Dashboard, SMART Health, Auto-Update, Auto-Backup, Email-Reports
# ==============================================================================

set -e

# --- FARBEN & DEKO ---
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${PURPLE}"
echo "  _____  ______ _____  _______     __  _   _           _____ "
echo " |  __ \|  ____|  __ \|  __ \ \   / / | \ | |   /\    / ____|"
echo " | |__) | |__  | |__) | |__) \ \_/ /  |  \| |  /  \  | (___  "
echo " |  ___/|  __| |  _  /|  _  / \   /   | . \  | / /\ \  \___ \ "
echo " | |    | |____| | \ \| | \ \  | |    | |\  |/ ____ \ ____) |"
echo " |_|    |______|_|  \_\_|  \_\ |_|    |_| \_/_/    \_\_____/ "
echo -e "${NC}"

# --- CHECK: ROOT ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Bitte als root ausführen: sudo $0${NC}"
    exit 1
fi

# --- 1. INSTALLATION DER BENÖTIGTEN PAKETE ---
echo -e "${GREEN}[1/6] Installiere System-Pakete...${NC}"
apt-get update
apt-get install -y nginx php-fpm smartmontools msmtp msmtp-mta mailutils rsync

# --- 2. KONFIGURATION: BERECHTIGUNGEN ---
echo -e "${GREEN}[2/6] Setze Berechtigungen (Webserver & SMART)...${NC}"
if ! grep -q "www-data ALL=(ALL) NOPASSWD: /usr/sbin/smartctl" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/smartctl" >> /etc/sudoers
fi

# Webverzeichnis vorbereiten
mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
# Setgid Bit setzen, damit neue Dateien zur Gruppe gehören
chmod g+s /var/www/html

# --- 3. DASHBOARD: BACKEND (data.php) ---
echo -e "${GREEN}[3/6] Erstelle Web-Backend...${NC}"
cat > /var/www/html/data.php << 'EOF'
<?php
header('Content-Type: application/json');

function get_cpu_temp() {
    $t = @file_get_contents('/sys/class/thermal/thermal_zone0/temp');
    return ['temp_c' => $t ? round((int)$t / 1000, 1) : 'N/A'];
}

function get_smart_health($dev) {
    if (!file_exists("/dev/$dev")) return 'OFFLINE';
    $output = shell_exec("sudo /usr/sbin/smartctl -H /dev/$dev 2>&1");
    if (strpos($output, 'PASSED') !== false) return 'OK';
    if (strpos($output, 'FAILED') !== false) return 'BAD';
    return 'UNKNOWN';
}

function get_disk_usage($path, $dev) {
    if (!is_dir($path)) return ['error' => 'Not mounted', 'health' => 'OFFLINE'];
    $total = disk_total_space($path);
    $free = disk_free_space($path);
    return [
        'total' => round($total / (1024**3), 2),
        'used' => round(($total - $free) / (1024**3), 2),
        'used_percent' => round((($total - $free) / $total) * 100, 1),
        'health' => get_smart_health($dev)
    ];
}

$last_backup = "Nie";
if (file_exists("/var/log/nas_backup.log")) {
    $last_line = shell_exec("grep 'beendet' /var/log/nas_backup.log | tail -1");
    if ($last_line) $last_backup = substr($last_line, 26, 16);
}

$status = [
    'hostname' => trim(shell_exec('hostname')),
    'uptime' => trim(shell_exec('uptime -p')),
    'disk1' => get_disk_usage('/mnt/perry-nas', 'sda'),
    'disk2' => get_disk_usage('/mnt/perry-nas-2', 'sdb'),
    'ram' => ['used_percent' => round(100 - (float)shell_exec("free | grep Mem | awk '{print $7/$2 * 100}'"), 1)],
    'cpu' => ['usage_percent' => round(100 - (float)shell_exec("top -bn1 | grep 'Cpu(s)' | awk '{print $8}'"), 1)],
    'temp' => get_cpu_temp(),
    'timestamp' => date('H:i:s'),
    'last_backup' => $last_backup
];
echo json_encode($status);
?>
EOF

# --- 4. DASHBOARD: FRONTEND (index.php) ---
echo -e "${GREEN}[4/6] Erstelle Pip-Boy Frontend...${NC}"
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <title>Perry-NAS Terminal</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: 'Courier New', monospace; background-color: #000; color: #39ff14; padding: 20px; }
        .container { width: 100%; max-width: 1200px; border: 4px solid #39ff14; padding: 25px; margin: auto; box-shadow: inset 0 0 15px #39ff14, 0 0 30px rgba(57, 255, 20, 0.3); }
        h1, h2 { text-align: center; text-transform: uppercase; border-bottom: 2px solid #39ff14; }
        .stats-grid, .grid-4 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 20px; margin-bottom: 25px; }
        .stat-box, .chart-container { border: 1px solid #39ff14; padding: 15px; }
        .progress-bar { height: 22px; background: #001a00; border: 1px solid #39ff14; position: relative; margin-top: 10px; }
        .progress-fill { height: 100%; background: #39ff14; width: 0%; transition: width 0.8s; }
        .progress-label { position: absolute; width: 100%; text-align: center; top: 0; color: #000; font-weight: bold; line-height: 22px; }
        .health-tag { font-weight: bold; float: right; }
        .bad { color: #ff0000 !important; text-shadow: 0 0 10px #ff0000; }
        .temp-display { font-size: 1.5em; text-align: center; border: 1px dashed #39ff14; margin: 5px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>[PERRY-NAS] >> SYSTEM_STATUS</h1>
        <div class="stats-grid">
            <div id="hostname-box">HOST: --</div>
            <div id="uptime-box">UPTIME: --</div>
            <div>BACKUP: <span id="backup-status">--</span></div>
        </div>
        <div class="grid-4">
            <div class="chart-container">
                <h3>CPU LOAD</h3>
                <div class="temp-display" id="temp-info">-- °C</div>
                <div class="progress-bar"><div class="progress-fill" id="cpu-fill"></div><span class="progress-label" id="cpu-percent">0%</span></div>
            </div>
            <div class="chart-container">
                <h3>RAM</h3>
                <div id="ram-info">Lade...</div>
                <div class="progress-bar"><div class="progress-fill" id="ram-fill"></div><span class="progress-label" id="ram-percent">0%</span></div>
            </div>
            <div class="chart-container">
                <h3>DISK 1 <span id="h1" class="health-tag"></span></h3>
                <div id="d1-info">Lade...</div>
                <div class="progress-bar"><div class="progress-fill" id="d1-fill"></div><span class="progress-label" id="d1-percent">0%</span></div>
            </div>
            <div class="chart-container">
                <h3>DISK 2 <span id="h2" class="health-tag"></span></h3>
                <div id="d2-info">Lade...</div>
                <div class="progress-bar"><div class="progress-fill" id="d2-fill"></div><span class="progress-label" id="d2-percent">0%</span></div>
            </div>
        </div>
    </div>
    <script>
        async function update() {
            try {
                const res = await fetch('data.php');
                const d = await res.json();
                document.getElementById('hostname-box').innerText = 'HOST: ' + d.hostname.toUpperCase();
                document.getElementById('uptime-box').innerText = 'UP: ' + d.uptime.toUpperCase();
                document.getElementById('backup-status').innerText = d.last_backup;
                document.getElementById('temp-info').innerText = d.temp.temp_c + ' °C';
                
                const setUI = (id, data, txt, hIdx) => {
                    document.getElementById(id+'-fill').style.width = data.used_percent + '%';
                    document.getElementById(id+'-percent').innerText = data.used_percent + '%';
                    if(txt) document.getElementById(id+'-info').innerText = txt;
                    if(hIdx) {
                        const h = document.getElementById('h'+hIdx);
                        h.innerText = '[SMART: ' + data.health + ']';
                        h.className = 'health-tag ' + (data.health === 'OK' ? '' : 'bad');
                    }
                };
                setUI('cpu', {used_percent: d.cpu.usage_percent});
                setUI('ram', d.ram, d.ram.used_percent + '%');
                setUI('d1', d.disk1, d.disk1.used + '/' + d.disk1.total + ' GB', '1');
                setUI('d2', d.disk2, d.disk2.used + '/' + d.disk2.total + ' GB', '2');
            } catch(e) {}
        }
        setInterval(update, 5000); update();
    </script>
</body>
</html>
EOF

# --- 5. AUTOMATISIERUNG: SCRIPTS ---
echo -e "${GREEN}[5/6] Erstelle Management-Skripte...${NC}"

# Update Skript
cat > /usr/local/bin/nas_update.sh << 'EOF'
#!/bin/bash
LOG_FILE="/tmp/nas_upgrade_list.txt"
echo "--- SYSTEM UPDATE REPORT: $(date +'%d.%m.%Y %H:%M') ---" > "$LOG_FILE"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1
UPGRADABLE=$(apt-get -s upgrade | grep "^Inst" | awk '{print "  [+] " $2 " (" $3 " -> " $4 ")"}' || true)
echo "Updates:" >> "$LOG_FILE"
echo "${UPGRADABLE:-Keine}" >> "$LOG_FILE"
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" > /dev/null 2>&1
apt-get autoremove -y > /dev/null 2>&1
[ -f /var/run/reboot-required ] && echo "!!! NEUSTART ERFORDERLICH !!!" >> "$LOG_FILE"
EOF

# Backup Skript
cat > /usr/local/bin/nas_backup.sh << 'EOF'
#!/bin/bash
SOURCE="/mnt/perry-nas/"
TARGET="/mnt/perry-nas-2/backup_daily/"
LOGFILE="/var/log/nas_backup.log"
mkdir -p "$TARGET"
echo "--- Backup Start: $(date) ---" >> "$LOGFILE"
rsync -av --delete "$SOURCE" "$TARGET" >> "$LOGFILE" 2>&1
EOF

# Report Skript (Email)
cat > /usr/local/bin/nas_report.sh << 'EOF'
#!/bin/bash
EMAIL="DEINE_EMAIL@gmail.com" # BITTE ANPASSEN
(
echo "Subject: PERRY-NAS Status-Report"
echo ""
echo "=== HARDWARE ==="
echo "Disk 1: $(sudo smartctl -H /dev/sda | grep 'test result' | cut -d: -f2)"
echo "Disk 2: $(sudo smartctl -H /dev/sdb | grep 'test result' | cut -d: -f2)"
echo ""
echo "=== UPDATES ==="
cat /tmp/nas_upgrade_list.txt 2>/dev/null
echo ""
echo "=== DISK SPACE ==="
df -h | grep -E '^Filesystem|/dev/sd'
) | msmtp "$EMAIL"
EOF

chmod +x /usr/local/bin/nas_*.sh

# --- 6. ZEITPLAN: CRONTAB ---
echo -e "${GREEN}[6/6] Richte Zeitplan (Cron) ein...${NC}"
cat > /etc/cron.d/perry_nas << 'EOF'
0 2 * * * root /usr/local/bin/nas_backup.sh
0 4 * * 1 root /usr/local/bin/nas_update.sh
0 8 * * 1 root /usr/local/bin/nas_report.sh
EOF

# Dienste neustarten
systemctl restart nginx
systemctl restart php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm

echo -e "${PURPLE}======================================================"
echo -e "INSTALLATION ABGESCHLOSSEN!"
echo -e "1. Passe deine Email in /usr/local/bin/nas_report.sh an."
echo -e "2. Konfiguriere msmtp in /etc/msmtprc für Gmail."
echo -e "3. Öffne das Dashboard im Browser via IP deines Pi."
echo -e "======================================================${NC}"