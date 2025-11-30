#!/bin/bash
# Perry-NAS Setup Script - Finale Version
# Raspberry Pi 5 NAS mit PCIe SATA Adapter & HomeRacker Gehäuse
# Kompatibel mit Debian Trixie | Kein Apache2 | Nur nginx

set -e

# --------------------------
# Farbdefinitionen
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
print_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --------------------------
# Banner
# --------------------------
echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#              PERRY-NAS                   #${NC}"
echo -e "${PURPLE}#    Raspberry Pi 5 NAS Setup              #${NC}"
echo -e "${PURPLE}#    mit PCIe SATA & HomeRacker            #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# --------------------------
# Root-Check
# --------------------------
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte führe das Skript als root aus: sudo $0"
fi

# --------------------------
# Konfiguration
# --------------------------
print_perry "Perry-NAS Konfiguration"
read -p "Perry-NAS Benutzername eingeben (z.B. perry): " PERRY_USER
PERRY_IP=$(hostname -I | awk '{print $1}')
PERRY_HOSTNAME="perry-nas"

# Hostname setzen
echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts
print_success "Hostname gesetzt: $PERRY_HOSTNAME"

# --------------------------
# Systemaktualisierung
# --------------------------
print_perry "Starte Systemaktualisierung..."
apt update && apt full-upgrade -y && apt autoremove -y

# --------------------------
# Pakete installieren (NUR nginx!)
# --------------------------
print_perry "Installiere Pakete..."
apt install -y \
    parted nginx php8.4-fpm samba ufw curl bc smartmontools hdparm git python3

# Dienste starten
systemctl enable --now nginx php8.4-fpm smbd smartd

# --------------------------
# PCIe SATA Hardware-Check
# --------------------------
print_perry "Prüfe PCIe SATA Hardware..."
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo ""
read -p "Device Name der PCIe Festplatte (z.B. sda): " DISK

[ -z "$DISK" ] && print_error "Kein Device angegeben"
[ ! -e "/dev/$DISK" ] && print_error "Device /dev/$DISK existiert nicht"

# --------------------------
# Festplatten-Handling MIT Erkennung bestehender Dateisysteme
# --------------------------
print_perry "Prüfe auf bestehendes Dateisystem..."
FSTYPE=$(lsblk -no FSTYPE "/dev/$DISK" | head -n1)

USE_EXISTING=false
if [[ -n "$FSTYPE" && "$FSTYPE" != "dos" && "$FSTYPE" != "" ]]; then
    print_warning "⚠️  Dateisystem '$FSTYPE' auf /dev/$DISK erkannt!"
    read -p "Möchten Sie dieses Dateisystem BEHALTEN? (j/N): " USE_EXISTING_INPUT
    [[ $USE_EXISTING_INPUT =~ ^[Jj]$ ]] && USE_EXISTING=true
fi

if [ "$USE_EXISTING" = true ]; then
    # Prüfe, ob Partition oder ganze Platte
    if lsblk -n "/dev/$DISK" | grep -q "part"; then
        PART="/dev/${DISK}1"
    else
        PART="/dev/$DISK"
    fi
    print_success "Verwende bestehendes Dateisystem auf $PART"
else
    print_perry "Erstelle neue Partition..."
    umount "/dev/${DISK}"* 2>/dev/null || true
    parted "/dev/$DISK" --script mklabel gpt
    parted "/dev/$DISK" --script mkpart primary ext4 0% 100%
    PART="/dev/${DISK}1"
    mkfs.ext4 -F "$PART"
fi

# Mount-Punkt
mkdir -p /mnt/perry-nas
echo "$PART /mnt/perry-nas ext4 defaults,noatime,data=writeback,nobarrier,nofail 0 2" >> /etc/fstab
mount -a

# Benutzer erstellen
id "$PERRY_USER" &>/dev/null || { useradd -m -s /bin/bash "$PERRY_USER"; passwd "$PERRY_USER"; }
chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

# --------------------------
# S.M.A.R.T. Monitoring
# --------------------------
print_perry "Richte S.M.A.R.T. Monitoring ein..."
smartctl --smart=on --saveauto=on "$PART"
cat > /etc/smartd.conf << EOF
$PART -a -o on -S on -s (S/../.././02|L/../../7/03) -m root -M exec /usr/share/smartmontools/smartd-runner
EOF
systemctl enable --now smartd
print_success "S.M.A.R.T. aktiviert"

# --------------------------
# Samba Konfiguration
# --------------------------
print_perry "Konfiguriere Samba..."
cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS ($PERRY_USER)
   security = user
   map to guest = bad user
   ntlm auth = yes
   server min protocol = SMB2
   client min protocol = SMB2
   server max protocol = SMB3
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   use sendfile = yes
   strict locking = no
   read raw = yes
   write raw = yes

[Perry-NAS]
   path = /mnt/perry-nas
   browseable = yes
   writable = yes
   guest ok = no
   valid users = $PERRY_USER
   force user = $PERRY_USER
EOF
smbpasswd -a "$PERRY_USER"
systemctl restart smbd
print_success "Samba eingerichtet"

# --------------------------
# Web-Interface (nginx + Perry-Theming)
# --------------------------
print_perry "Richte Web-Interface ein..."
chown -R www-data:www-data /var/www/html
rm -f /var/www/html/index.nginx-debian.html

# PHP-FPM Einstellungen
sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.4/fpm/php.ini

# Nginx Konfiguration
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    root /var/www/html;
    index index.php index.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

# Perry-Themed Web-Interface (aus deinem README)
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🍐 Perry-NAS Status</title>
    <style>
        :root { --perry-primary: #8A2BE2; --perry-secondary: #9370DB; --perry-dark: #483D8B; }
        body { font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, var(--perry-primary), var(--perry-secondary)); min-height: 100vh; padding: 20px; color: #333; }
        .perry-container { max-width: 1200px; margin: 0 auto; }
        .perry-header { text-align: center; margin-bottom: 30px; color: white; }
        .perry-header h1 { font-size: 3em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .perry-card { background: rgba(255,255,255,0.95); border-radius: 15px; padding: 25px; margin-bottom: 25px; box-shadow: 0 8px 32px rgba(0,0,0,0.1); }
        .perry-card h2 { color: var(--perry-dark); border-bottom: 3px solid var(--perry-primary); padding-bottom: 10px; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 8px; overflow-x: auto; font-family: monospace; }
        .perry-footer { text-align: center; margin-top: 30px; color: white; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="perry-container">
        <header class="perry-header">
            <h1>🍐 Perry-NAS</h1>
            <div class="subtitle">Dein persönlicher NAS-Server</div>
        </header>
        <div class="perry-card">
            <h2>📊 Systemübersicht</h2>
            <pre><?php 
                echo "Hostname: " . trim(shell_exec('hostname')) . "\n";
                echo "IP: " . trim(shell_exec('hostname -I')) . "\n";
                echo "Uptime: " . trim(shell_exec('uptime -p'));
            ?></pre>
        </div>
        <div class="perry-card">
            <h2>💾 Speicher</h2>
            <pre><?php system('df -h /mnt/perry-nas'); ?></pre>
        </div>
        <div class="perry-card">
            <h2>🔧 Dienste</h2>
            <pre><?php
                $services = ['smbd', 'nginx', 'php8.4-fpm', 'smartd'];
                foreach ($services as $svc) {
                    $status = trim(shell_exec("systemctl is-active $svc 2>/dev/null"));
                    echo "$svc: " . ($status === 'active' ? '✅ aktiv' : '❌ inaktiv') . "\n";
                }
            ?></pre>
        </div>
        <footer class="perry-footer">
            <p>🍐 Perry-NAS - Dein zuverlässiger Speicherpartner</p>
        </footer>
    </div>
</body>
</html>
EOF

systemctl restart nginx php8.4-fpm
print_success "Web-Interface eingerichtet"

# --------------------------
# Firewall
# --------------------------
print_perry "Aktiviere Firewall..."
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow samba
print_success "Firewall aktiviert"

# --------------------------
# Täglicher E-Mail-Statusbericht (wie gewünscht!)
# --------------------------
print_perry "Möchten Sie einen täglichen HTML-Statusbericht per E-Mail erhalten?"
read -p "(j/N): " SETUP_EMAIL

if [[ $SETUP_EMAIL =~ ^[Jj]$ ]]; then
    print_perry "SMTP-Konfiguration:"
    read -p "  SMTP-Server (z.B. smtp.gmail.com): " SMTP_SERVER
    read -p "  SMTP-Port (587): " SMTP_PORT
    read -p "  Absender-E-Mail: " SENDER_EMAIL
    read -s -p "  App-Passwort: " SENDER_PASSWORD; echo
    read -p "  Empfänger (kommagetrennt): " RECIPIENTS

    # sudoers für smartctl
    echo "$PERRY_USER ALL=(root) NOPASSWD: /usr/sbin/smartctl" > /etc/sudoers.d/perry-smartctl
    chmod 440 /etc/sudoers.d/perry-smartctl

    # Skriptverzeichnis
    SCRIPT_DIR="/home/$PERRY_USER/perry-nas/scripts"
    mkdir -p "$SCRIPT_DIR"

    # Konfigurationsdatei
    cat > "/home/$PERRY_USER/.perry-nas-email.conf" << EOF
smtp_server=$SMTP_SERVER
smtp_port=$SMTP_PORT
sender_email=$SENDER_EMAIL
sender_password=$SENDER_PASSWORD
recipients=$RECIPIENTS
nas_mount=/mnt/perry-nas
EOF
    chown $PERRY_USER:$PERRY_USER "/home/$PERRY_USER/.perry-nas-email.conf"
    chmod 600 "/home/$PERRY_USER/.perry-nas-email.conf"

    # Python-Skript
    cat > "$SCRIPT_DIR/daily-status-email.py" << 'EOF'
#!/usr/bin/env python3
import smtplib, subprocess, os, configparser, json
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

conf_path = os.path.expanduser("~/.perry-nas-email.conf")
config = {}
with open(conf_path) as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            config[k] = v

def run(cmd): return subprocess.check_output(cmd, shell=True).decode().strip()

# Systemstatus
status = {
    'hostname': run('hostname'),
    'ip': run('hostname -I'),
    'uptime': run('uptime -p'),
    'disk': run(f'df -h {config["nas_mount"]}'),
    'temp': f"{int(run('cat /sys/class/thermal/thermal_zone0/temp')) / 1000:.1f}°C",
    'services': {
        'Samba': run('systemctl is-active smbd'),
        'nginx': run('systemctl is-active nginx'),
        'PHP-FPM': run('systemctl is-active php8.4-fpm'),
        'S.M.A.R.T.': run('systemctl is-active smartd')
    }
}

# S.M.A.R.T. Summary
smart_html = "N/A"
try:
    disks = run("lsblk -dno NAME | grep -E '^(sd|nvme)'").split()
    for d in disks:
        out = run(f"sudo smartctl -a /dev/{d}")
        temp = next((line.split()[-1] + "°C" for line in out.splitlines() if line.strip().startswith("194 Temperature_Celsius")), "N/A")
        health = "OK" if "PASSED" in out else "FAILED"
        smart_html = f"/dev/{d}: {health} | {temp}"
        break
except: smart_html = "Error"

html = f"""
<h2>🍐 Perry-NAS Status – {datetime.now().strftime('%d.%m.%Y %H:%M')}</h2>
<p><b>System:</b> {status['hostname']} ({status['ip']}) | {status['uptime']} | {status['temp']}</p>
<h3>Dienste</h3>
<table border=1><tr><th>Dienst</th><th>Status</th></tr>
{"".join(f"<tr><td>{k}</td><td>{v}</td></tr>" for k,v in status['services'].items())}
</table>
<h3>Speicher</h3><pre>{status['disk']}</pre>
<h3>S.M.A.R.T.</h3>{smart_html}
<p>----------</p><p>Viele Grüße,<br>Euer Perry-NAS</p>
"""
msg = MIMEMultipart("alternative")
msg['Subject'] = f"🍐 Perry-NAS Status – {datetime.now().strftime('%d.%m.%Y')}"
msg['From'] = config['sender_email']
msg['To'] = config['recipients']
msg.attach(MIMEText(html, 'html'))

server = smtplib.SMTP(config['smtp_server'], int(config['smtp_port']))
server.starttls()
server.login(config['sender_email'], config['sender_password'])
server.send_message(msg)
server.quit()
print("✅ E-Mail gesendet")
EOF

    chown -R $PERRY_USER:$PERRY_USER "$SCRIPT_DIR"
    chmod +x "$SCRIPT_DIR/daily-status-email.py"

    # Cron-Job
    (crontab -u $PERRY_USER -l 2>/dev/null; echo "0 8 * * * /usr/bin/python3 $SCRIPT_DIR/daily-status-email.py") | crontab -u $PERRY_USER -
    print_success "Täglicher E-Mail-Statusbericht um 08:00 Uhr eingerichtet"
fi

# --------------------------
# Abschluss
# --------------------------
echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#           PERRY-NAS BEREIT!              #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo -e "${GREEN}✅ Perry-NAS Setup abgeschlossen!${NC}"
echo ""
echo -e "${CYAN}🌐 Zugriff:${NC}"
echo -e "   Web: http://$PERRY_IP"
echo -e "   Samba: \\\\\\$PERRY_IP\\Perry-NAS"
echo -e "   SSH: ssh $PERRY_USER@$PERRY_IP"
echo ""
echo -e "${GREEN}🍐 Perry-NAS ist einsatzbereit! Viel Spaß!${NC}"