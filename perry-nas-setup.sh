#!/bin/bash
# Perry-NAS Setup Script – Finale Version gemäß README.md
# Raspberry Pi 5 • HomeRacker • PCIe SATA • Debian Trixie • nginx only

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

echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#              PERRY-NAS                   #${NC}"
echo -e "${PURPLE}#    Raspberry Pi 5 + HomeRacker + PCIe    #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# Root-Check
[ "$EUID" -ne 0 ] && print_error "Bitte als root ausführen: sudo $0"

# Benutzer
read -p "Perry-NAS Benutzername (z.B. perry): " PERRY_USER
PERRY_HOSTNAME="perry-nas"
echo "$PERRY_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PERRY_HOSTNAME/g" /etc/hosts
print_success "Hostname gesetzt"

# System-Update
print_perry "Aktualisiere System..."
apt update && apt full-upgrade -y && apt autoremove -y

# Pakete (nur wie in README.md)
print_perry "Installiere Pakete gemäß README.md..."
apt install -y \
    parted nginx php8.4-fpm samba ufw curl bc smartmontools hdparm git python3

# PCIe SATA Optimierung (wie in README.md beschrieben)
print_perry "PCIe SATA Optimierung (wie in README.md)..."
echo 'max_performance' | tee /sys/class/scsi_host/host*/link_power_management_policy >/dev/null 2>&1 || true
echo '- - -' | tee /sys/class/scsi_host/host*/scan >/dev/null 2>&1 || true

# Festplatten-Erkennung
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
read -p "PCIe Festplatte (z.B. sda): " DISK
[ -z "$DISK" ] && print_error "Kein Device angegeben"
[ ! -e "/dev/$DISK" ] && print_error "Device /dev/$DISK existiert nicht"

PART="/dev/${DISK}1"
FSTYPE=$(lsblk -no FSTYPE "$PART" 2>/dev/null | head -n1)

if [[ -n "$FSTYPE" && "$FSTYPE" != "dos" ]]; then
    print_success "✅ Dateisystem '$FSTYPE' erkannt – wird BEHALTEN (wie in README.md empfohlen)!"
    USE_EXISTING=true
else
    print_warning "⚠️  Kein gültiges Dateisystem gefunden."
    read -p "Neue ext4-Partition erstellen? (J/n): " CREATE
    if [[ ! $CREATE =~ ^[Nn]$ ]]; then
        umount "$PART" 2>/dev/null || true
        parted "/dev/$DISK" --script mklabel gpt
        parted "/dev/$DISK" --script mkpart primary ext4 0% 100%
        mkfs.ext4 -F "$PART"
    else
        print_error "Abbruch"
    fi
fi

# Mount mit Performance-Optionen (wie in README.md)
mkdir -p /mnt/perry-nas
echo "$PART /mnt/perry-nas ext4 defaults,noatime,data=writeback,nobarrier,nofail 0 2" >> /etc/fstab
mount -a

# Benutzer
id "$PERRY_USER" &>/dev/null || { useradd -m -s /bin/bash "$PERRY_USER"; passwd "$PERRY_USER"; }
chown -R $PERRY_USER:$PERRY_USER /mnt/perry-nas
chmod -R 775 /mnt/perry-nas

# Samba (wie in README.md)
print_perry "Richte Samba gemäß README.md ein..."
cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS ($PERRY_USER)
   security = user
   map to guest = bad user
   ntlm auth = yes
   server min protocol = SMB2
   # PCIe Optimierungen aus README.md
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   use sendfile = yes
   strict locking = no
   read raw = yes
   write raw = yes

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

# 🖥️ DASHBOARD – Web-Interface (wie in README.md)
print_perry "Richte Perry-NAS Web-Interface ein (wie in README.md)..."
# ✅ KORREKT: www-data (nicht www-www-data!)
chown -R www-data /var/www/html
rm -f /var/www/html/index.nginx-debian.html

# PHP-FPM
PHP_INI_FILE="/etc/php/8.4/fpm/php.ini"
if [ -f "$PHP_INI_FILE" ]; then
    sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0;' "$PHP_INI_FILE"
    print_success "PHP-FPM php.ini angepasst"
else
    print_warning "PHP-FPM php.ini nicht gefunden – überspringe cgi.fix_pathinfo"
fi

# Nginx (wie in README.md)
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    root /var/www/html;
    index index.php;
    server_name _;
    location / {
        try_files $uri $uri/ =404;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

# Perry-Themed Web-Interface (wie in README.md beschrieben)
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
            --perry-dark: #483D8B;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, var(--perry-primary), var(--perry-secondary));
            min-height: 100vh;
            padding: 20px;
            color: white;
        }
        .perry-container { max-width: 1000px; margin: 0 auto; }
        .perry-header { text-align: center; margin-bottom: 30px; }
        .perry-header h1 { font-size: 2.5em; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .perry-card {
            background: rgba(255,255,255,0.95);
            color: #333;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        pre { background: #f0f0f0; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="perry-container">
        <header class="perry-header">
            <h1>🍐 Perry-NAS Dashboard</h1>
        </header>
        <div class="perry-card">
            <h2>📊 Systemübersicht</h2>
            <pre><?php
                echo "Hostname: " . trim(shell_exec('hostname')) . "\n";
                echo "IP: " . trim(shell_exec('hostname -I')) . "\n";
                echo "Uptime: " . trim(shell_exec('uptime -p')) . "\n";
                echo "OS: " . trim(shell_exec('lsb_release -d 2>/dev/null | cut -f2')) . "\n";
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
        <div class="perry-card">
            <h2>🌡️ Temperatur</h2>
            <pre><?php
                $temp = intval(shell_exec('cat /sys/class/thermal/thermal_zone0/temp'));
                echo "System: " . ($temp / 1000) . "°C\n";
            ?></pre>
        </div>
    </div>
</body>
</html>
EOF

systemctl enable --now nginx php8.4-fpm
print_success "Dashboard aktiviert – erreichbar unter http://<IP>"

# Firewall (wie in README.md)
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow samba
print_success "Firewall aktiviert"

# ❤️ S.M.A.R.T. Monitoring (wie in README.md)
print_perry "Richte S.M.A.R.T. Monitoring ein (wie in README.md)..."
smartctl --smart=on --saveauto=on "$PART" || print_warning "S.M.A.R.T. nicht unterstützt"
echo "$PART -a -o on -S on -s (S/../.././02|L/../../7/03) -m root" > /etc/smartd.conf

# Smartd erst JETZT starten (nach Mount & Web → kein Timeout!)
systemctl start smartd
systemctl enable smartd
print_success "S.M.A.R.T. Monitoring aktiviert"

# 📧 Täglicher E-Mail-Statusbericht (optional, aber README-konform)
print_perry "Möchten Sie einen täglichen HTML-Statusbericht per E-Mail erhalten? (wie in README.md vorgesehen)"
read -p "(j/N): " SETUP_EMAIL

if [[ $SETUP_EMAIL =~ ^[Jj]$ ]]; then
    print_perry "SMTP-Konfiguration:"
    read -p "  SMTP-Server (z.B. smtp.gmail.com): " SMTP_SERVER
    read -p "  SMTP-Port (587): " SMTP_PORT
    read -p "  Absender-E-Mail: " SENDER_EMAIL
    read -s -p "  App-Passwort: " SENDER_PASSWORD; echo
    read -p "  Empfänger (kommagetrennt): " RECIPIENTS

    # sudoers für smartctl (für E-Mail-Skript)
    echo "$PERRY_USER ALL=(root) NOPASSWD: /usr/sbin/smartctl" > /etc/sudoers.d/perry-smartctl
    chmod 440 /etc/sudoers.d/perry-smartctl

    # Skriptordner
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

    # 📨 E-Mail-Skript
    cat > "$SCRIPT_DIR/daily-status-email.py" << 'EOF'
#!/usr/bin/env python3
import smtplib, subprocess, os, configparser
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

config_path = os.path.expanduser("~/.perry-nas-email.conf")
config = {}
with open(config_path) as f:
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
try:
    out = run("sudo smartctl -a /dev/sda")
    temp = next((line.split()[-1] + "°C" for line in out.splitlines() if line.strip().startswith("194 Temperature_Celsius")), "N/A")
    health = "OK" if "PASSED" in out else "FAILED"
    smart_html = f"/dev/sda: {health} | {temp}"
except:
    smart_html = "Fehler beim Lesen von S.M.A.R.T."

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
EOF

    chown -R $PERRY_USER:$PERRY_USER "$SCRIPT_DIR"
    chmod +x "$SCRIPT_DIR/daily-status-email.py"

    # 🕒 Cron-Job (wie in README.md vorgesehen: Autostart + täglicher Bericht)
    (crontab -u $PERRY_USER -l 2>/dev/null; echo "
# Perry-NAS
0 8 * * * /usr/bin/python3 $SCRIPT_DIR/daily-status-email.py
") | crontab -u $PERRY_USER -

    print_success "📧 Täglicher E-Mail-Statusbericht um 08:00 Uhr eingerichtet"
fi

# 🎉 Fertig – wie in README.md beschrieben
IP=$(hostname -I | awk '{print $1}')
echo -e "\n${GREEN}🎉 Perry-NAS Setup abgeschlossen!${NC}"
echo -e "${GREEN}🖥️  Dashboard: http://$IP${NC}"
echo -e "${GREEN}💾 Samba: \\\\\\\\$IP\\\\Perry-NAS${NC}"
echo -e "${GREEN}📧 E-Mail: Täglich um 08:00 Uhr (falls aktiviert)${NC}"
echo -e "${GREEN}🔒 Alle Dienste laufen – inkl. S.M.A.R.T. und PCIe-Optimierung${NC}"
echo -e "\n${PURPLE}🍐 Perry-NAS – Dein zuverlässiger Speicherpartner!${NC}"