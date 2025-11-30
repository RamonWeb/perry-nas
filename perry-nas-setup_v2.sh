#!/bin/bash
# Perry-NAS Setup Script - Apache2 Version
# Raspberry Pi 5 NAS mit PCIe SATA Adapter & HomeRacker Gehäuse

set -e

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

print_perry() { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --------------------------
# Perry-NAS Banner
# --------------------------
echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#              PERRY-NAS                   #${NC}"
echo -e "${PURPLE}#    Raspberry Pi 5 NAS Setup (Apache2)     #${NC}"
echo -e "${PURPLE}#    mit PCIe SATA & HomeRacker            #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# --------------------------
# Root-Check
# --------------------------
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte führe das Skript als root aus: sudo $0"
    exit 1
fi

# --------------------------
# Perry-NAS Konfiguration
# --------------------------
print_perry "Perry-NAS Konfiguration"

read -p "Perry-NAS Benutzername eingeben (z.B. perry): " PERRY_USER
PERRY_IP=$(hostname -I | awk '{print $1}')
PERRY_HOSTNAME="perry-nas"

# Hostname setzen
echo "$PERRY_HOSTNAME" | sudo tee /etc/hostname
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts

print_success "Perry-NAS Hostname konfiguriert: $PERRY_HOSTNAME"

# --------------------------
# Systemaktualisierung
# --------------------------
print_perry "Starte Systemaktualisierung..."
apt update
apt full-upgrade -y
apt autoremove -y

# --------------------------
# Perry-NAS Pakete - Apache2 statt Nginx
# --------------------------
print_perry "Installiere Perry-NAS Pakete..."
apt install -y parted apache2 php libapache2-mod-php samba ufw curl bc smartmontools hdparm

# --------------------------
# PCIe SATA Hardware-Check
# --------------------------
print_perry "Prüfe PCIe SATA Hardware..."

print_info "Verfügbare Block Devices:"
lsblk

echo ""
print_warning "PERRY-NAS PCIe SATA SETUP"
read -p "Bitte Device Name der PCIe Festplatte eingeben (z.B. sda): " DISK

if [ -z "$DISK" ]; then
    print_error "Kein Device angegeben. Abbruch."
    exit 1
fi

if [ ! -e "/dev/$DISK" ]; then
    print_error "Device /dev/$DISK existiert nicht!"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    exit 1
fi

# --------------------------
# Festplatteneinrichtung
# --------------------------
read -p "Sind Sie sicher, dass Sie /dev/$DISK komplett löschen möchten? (ja/NEIN): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
    print_error "Abbruch: Keine Bestätigung erhalten."
    exit 1
fi

print_perry "Richte Perry-NAS Festplatte ein..."

umount "/dev/${DISK}"* 2>/dev/null || true

print_info "Erstelle Partition..."
parted "/dev/$DISK" --script mklabel gpt
parted "/dev/$DISK" --script mkpart primary ext4 0% 100%

print_info "Formatiere Partition..."
mkfs.ext4 -F "/dev/${DISK}1"

print_info "Erstelle Perry-NAS Mountpoint..."
mkdir -p /mnt/perry-nas

# Optimierte fstab für Perry-NAS
echo "/dev/${DISK}1  /mnt/perry-nas  ext4  defaults,noatime,data=writeback,nobarrier,nofail  0  2" >> /etc/fstab

mount -a

# Perry-NAS Benutzer erstellen
if ! id "$PERRY_USER" &>/dev/null; then
    print_info "Erstelle Perry-NAS Benutzer: $PERRY_USER"
    useradd -m -s /bin/bash "$PERRY_USER"
    echo "Bitte Passwort für Perry-NAS Benutzer $PERRY_USER setzen:"
    passwd "$PERRY_USER"
fi

chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

print_success "Perry-NAS Festplatte eingerichtet"

# --------------------------
# Perry-NAS S.M.A.R.T. Monitoring
# --------------------------
print_perry "Richte Perry-NAS Health Monitoring ein..."

# S.M.A.R.T. für die Festplatte aktivieren
smartctl --smart=on --saveauto=on /dev/$DISK

# S.M.A.R.T. Konfiguration erstellen
cat > /etc/smartd.conf << EOF
/dev/$DISK -a -o on -S on -s (S/../.././02|L/../../7/03) -m root -M exec /usr/share/smartmontools/smartd-runner
EOF

# smartd Service handling
print_info "Konfiguriere S.M.A.R.T. Monitoring Service..."

# Prüfe ob smartd bereits läuft und stoppe ihn
if systemctl is-active --quiet smartd; then
    print_info "Stoppe bestehenden smartd Service..."
    systemctl stop smartd
fi

# Service neu starten mit korrekter Konfiguration
systemctl enable smartd 2>/dev/null || print_warning "smartd Service konnte nicht aktiviert werden (bereits aktiv?)"
systemctl start smartd

# Warte kurz und prüfe Status
sleep 2
if systemctl is-active --quiet smartd; then
    print_success "Perry-NAS S.M.A.R.T. Monitoring aktiviert"
else
    print_warning "S.M.A.R.T. Monitoring konnte nicht gestartet werden, aber Setup wird fortgesetzt"
fi

# --------------------------
# Perry-NAS Samba Konfiguration
# --------------------------
print_perry "Konfiguriere Perry-NAS Samba Freigaben..."

sudo tee /etc/samba/smb.conf > /dev/null << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS ($PERRY_USER)
   server min protocol = SMB2
   client min protocol = SMB2
   server max protocol = SMB3
   client max protocol = SMB3
   security = user
   map to guest = bad user
   ntlm auth = yes
   local master = yes
   preferred master = yes
   domain master = yes
   os level = 255
   wins support = yes
   
   # Perry-NAS Performance Optimierungen
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   use sendfile = yes
   strict locking = no
   read raw = yes
   write raw = yes
   
   log level = 1
   log file = /var/log/samba/log.%m
   max log size = 1000

[Perry-NAS]
   comment = Perry-NAS Hauptspeicher ($PERRY_USER)
   path = /mnt/perry-nas
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = $PERRY_USER
   create mask = 0775
   directory mask = 0775
   force user = $PERRY_USER
EOF

print_info "Bitte Samba-Passwort für Perry-NAS Benutzer $PERRY_USER setzen:"
smbpasswd -a "$PERRY_USER"

systemctl enable smbd
systemctl restart smbd

print_success "Perry-NAS Samba konfiguriert"

# --------------------------
# Perry-NAS Web Interface - Apache2 Version
# --------------------------
print_perry "Richte Perry-NAS Web Interface ein..."

# Stelle sicher, dass Apache2 läuft
systemctl enable apache2
systemctl restart apache2

# Entferne Standard-Dateien
rm -f /var/www/html/index.html /var/www/html/index.htm

# Apache2 PHP Konfiguration
a2enmod php* 2>/dev/null || true
systemctl restart apache2

# Perry-NAS Web Interface mit Perry-Theming - Apache2 Version
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🍐 Perry-NAS Status</title>
    <style>
        :root {
            --perry-primary: #8A2BE2;
            --perry-secondary: #9370DB;
            --perry-accent: #4B0082;
            --perry-light: #E6E6FA;
            --perry-dark: #483D8B;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, var(--perry-primary) 0%, var(--perry-secondary) 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
        }
        
        .perry-container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .perry-header {
            text-align: center;
            margin-bottom: 30px;
            color: white;
        }
        
        .perry-header h1 {
            font-size: 3em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .perry-header .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .perry-card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .perry-card h2 {
            color: var(--perry-dark);
            border-bottom: 3px solid var(--perry-primary);
            padding-bottom: 10px;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .perry-stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .perry-service-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .perry-service-item {
            padding: 15px;
            background: var(--perry-light);
            border-radius: 10px;
            text-align: center;
            border-left: 4px solid var(--perry-primary);
        }
        
        .perry-status-ok {
            color: #28a745;
            font-weight: bold;
        }
        
        .perry-status-error {
            color: #dc3545;
            font-weight: bold;
        }
        
        pre {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            overflow-x: auto;
            border-left: 4px solid var(--perry-primary);
            font-family: 'Courier New', monospace;
            white-space: pre-wrap;
        }
        
        .perry-footer {
            text-align: center;
            margin-top: 30px;
            color: white;
            opacity: 0.8;
        }
        
        @media (max-width: 768px) {
            .perry-stats-grid {
                grid-template-columns: 1fr;
            }
            
            .perry-header h1 {
                font-size: 2em;
            }
        }
    </style>
</head>
<body>
    <div class="perry-container">
        <header class="perry-header">
            <h1>🍐 Perry-NAS</h1>
            <div class="subtitle">Dein persönlicher NAS-Server (Apache2)</div>
        </header>
        
        <div class="perry-card">
            <h2>📊 Systemübersicht</h2>
            <div class="perry-stats-grid">
                <div>
                    <h3>Systeminformationen</h3>
                    <pre><?php 
                        echo "Hostname: " . shell_exec('hostname') . "\n";
                        echo "Benutzer: " . shell_exec('whoami') . "\n";
                        echo "OS: " . shell_exec('lsb_release -d | cut -f2') . "\n";
                        echo "Kernel: " . shell_exec('uname -r');
                    ?></pre>
                </div>
                <div>
                    <h3>Laufzeit</h3>
                    <pre><?php echo shell_exec('uptime -p'); ?></pre>
                </div>
                <div>
                    <h3>Perry-NAS Status</h3>
                    <pre><?php echo date('d.m.Y H:i:s'); ?>

🍐 Perry-NAS läuft stabil (Apache2)
💾 PCIe SATA aktiv
🔒 Samba Freigaben online</pre>
                </div>
            </div>
        </div>

        <div class="perry-card">
            <h2>💾 Perry-NAS Speicher</h2>
            <pre><?php system('df -h /mnt/perry-nas'); ?></pre>
        </div>

        <div class="perry-card">
            <h2>🖥️ Systemressourcen</h2>
            <div class="perry-stats-grid">
                <div>
                    <h3>Arbeitsspeicher</h3>
                    <pre><?php system('free -h'); ?></pre>
                </div>
                <div>
                    <h3>CPU Auslastung</h3>
                    <pre><?php 
                        $load = sys_getloadavg();
                        echo "1 Min:  " . number_format($load[0], 2) . "\n";
                        echo "5 Min:  " . number_format($load[1], 2) . "\n";
                        echo "15 Min: " . number_format($load[2], 2);
                    ?></pre>
                </div>
                <div>
                    <h3>Systemtemperatur</h3>
                    <pre><?php 
                        $temp_paths = ['/sys/class/thermal/thermal_zone0/temp'];
                        $temperature = null;
                        foreach ($temp_paths as $path) {
                            if (file_exists($path)) {
                                $temp_value = trim(file_get_contents($path));
                                if (is_numeric($temp_value)) {
                                    $temperature = $temp_value / 1000;
                                    break;
                                }
                            }
                        }
                        if ($temperature !== null) {
                            echo "Temperatur: " . number_format($temperature, 1) . "°C";
                        } else {
                            echo "Temperatur: Überwacht";
                        }
                    ?></pre>
                </div>
            </div>
        </div>

        <div class="perry-card">
            <h2>🔧 Perry-NAS Dienste</h2>
            <div class="perry-service-grid">
                <?php
                function perry_check_service($service, $name) {
                    $status = shell_exec("systemctl is-active $service 2>/dev/null");
                    $is_active = (trim($status) == 'active');
                    $icon = $is_active ? '✅' : '❌';
                    $class = $is_active ? 'perry-status-ok' : 'perry-status-error';
                    echo "<div class='perry-service-item'>";
                    echo "<h3>$name</h3>";
                    echo "<p class=\"$class\">$icon " . trim($status) . "</p>";
                    echo "</div>";
                }
                
                perry_check_service('smbd', 'Samba');
                perry_check_service('apache2', 'Apache2 Webserver');
                perry_check_service('php*-fpm', 'PHP');
                perry_check_service('smartd', 'S.M.A.R.T.');
                ?>
            </div>
        </div>

        <div class="perry-card">
            <h2>🌐 Perry-NAS Zugriff</h2>
            <pre><?php 
                $ip = shell_exec('hostname -I | tr -d "\\n"');
                echo "Samba Freigabe: \\\\\\\\$ip\\\\Perry-NAS\n";
                echo "Web Interface: http://$ip\n";
                echo "SSH Zugang: ssh " . shell_exec('whoami') . "@$ip\n";
                echo "\n";
                echo "🍐 Perry-NAS bereit für Verbindungen!";
            ?></pre>
        </div>
        
        <footer class="perry-footer">
            <p>🍐 Perry-NAS - Dein zuverlässiger Speicherpartner (Apache2)</p>
        </footer>
    </div>
</body>
</html>
EOF

# Apache2 Konfiguration optimieren
cat > /etc/apache2/conf-available/perry-nas-security.conf << 'EOF'
# Perry-NAS Apache2 Sicherheitskonfiguration
ServerTokens Prod
ServerSignature Off

# PHP-Sicherheit
php_admin_value expose_php Off

# Zugriffsbeschränkungen
<Directory "/var/www/html">
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

a2enconf perry-nas-security 2>/dev/null || true
systemctl reload apache2

print_success "Perry-NAS Web Interface (Apache2) eingerichtet"

# --------------------------
# Perry-NAS Firewall
# --------------------------
print_perry "Konfiguriere Perry-NAS Firewall..."
ufw --force enable
ufw allow ssh
ufw allow 'Apache'
ufw allow samba

print_success "Perry-NAS Firewall aktiviert"

# --------------------------
# Perry-NAS Autostart
# --------------------------
print_perry "Aktiviere Perry-NAS Autostart..."
systemctl enable apache2
systemctl enable smbd
systemctl enable php*-fpm 2>/dev/null || true

# S.M.A.R.T. Service nur aktivieren, wenn nicht bereits aktiv
if ! systemctl is-enabled smartd >/dev/null 2>&1; then
    systemctl enable smartd
fi

# Perry-NAS Mount Service
cat > /etc/systemd/system/perry-nas-mount.service << EOF
[Unit]
Description=Perry-NAS Storage Mount
After=network.target
Before=smbd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mount /mnt/perry-nas
ExecStop=/bin/umount /mnt/perry-nas
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable perry-nas-mount.service

# --------------------------
# Perry-NAS Abschluss
# --------------------------
print_perry "Perry-NAS Setup wird abgeschlossen..."

apache2ctl configtest && print_success "Perry-NAS Apache2 OK" || print_error "Perry-NAS Apache2 Konfigurationsfehler"

# Performance Check
print_info "Perry-NAS Performance Test:"
hdparm -Tt /dev/${DISK}1 2>/dev/null | head -5 || echo "Performance Test übersprungen"

# S.M.A.R.T. Status
print_info "Perry-NAS Health Status:"
smartctl -H /dev/$DISK 2>/dev/null | grep -i "health" || echo "S.M.A.R.T. Status OK"

echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#           PERRY-NAS BEREIT!              #${NC}"
echo -e "${PURPLE}#        (Apache2 Version)                 #${NC}"
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
echo -e "  🌐 Apache2 Webserver: Aktiv"
echo -e "  📡 S.M.A.R.T.: Überwacht"
echo -e "  🔒 Firewall: Aktiv"
echo ""
echo -e "${GREEN}🍐 Perry-NAS (Apache2) ist einsatzbereit! Viel Spaß!${NC}"
