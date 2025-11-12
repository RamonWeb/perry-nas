#!/bin/bash
# Perry-NAS Komplettsetup für Debian Trixie

set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Root-Check
if [ "$EUID" -ne 0 ]; then
    error "Bitte als root ausführen: sudo $0"
    exit 1
fi

echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#         PERRY-NAS KOMPLETTSETUP          #${NC}"
echo -e "${PURPLE}#         Für Debian Trixie                #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# --------------------------
# System-Update
# --------------------------
log "Aktualisiere System..."
apt update
apt upgrade -y
success "System aktualisiert"

# --------------------------
# Basis-Pakete installieren
# --------------------------
log "Installiere Basis-Pakete..."
apt install -y \
    nginx \
    samba \
    samba-common-bin \
    curl \
    wget \
    htop \
    tree \
    git \
    build-essential \
    ufw \
    openssh-server \
    python3 \
    python3-pip \
    jq \
    smartmontools \
    rsync \
    ca-certificates

success "Basis-Pakete installiert"

# --------------------------
# Benutzer einrichten
# --------------------------
log "Richte Benutzer ein..."

# Haupt-Benutzer
if ! id "ramon" &>/dev/null; then
    useradd -m -s /bin/bash ramon
    usermod -aG sudo ramon
    success "Benutzer 'ramon' erstellt"
fi

# Samba-Benutzer
if ! id "nasuser" &>/dev/null; then
    useradd -m -s /bin/bash nasuser
    echo "nasuser:nasuser123" | chpasswd
    success "Samba-Benutzer 'nasuser' erstellt"
fi

# --------------------------
# Samba konfigurieren
# --------------------------
log "Konfiguriere Samba..."

# Samba Konfiguration
cat > /etc/samba/smb.conf << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = Perry-NAS
   security = user
   map to guest = bad user
   dns proxy = no

# Logs
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d

# Performance
   socket options = TCP_NODELAY SO_RCVBUF=65536 SO_SNDBUF=65536
   use sendfile = yes

# Shares
[public]
   path = /mnt/perry-nas/public
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[home]
   path = /mnt/perry-nas/home
   browseable = yes
   read only = no
   valid users = nasuser
   create mask = 0770
   directory mask = 0770
EOF

# Samba-Benutzer einrichten
(echo "nasuser123"; echo "nasuser123") | smbpasswd -a -s nasuser

success "Samba konfiguriert"

# --------------------------
# Dateisystem einrichten
# --------------------------
log "Richte Dateisystem ein..."

# Erstelle Mount-Point
mkdir -p /mnt/perry-nas
mkdir -p /mnt/perry-nas/{public,home,backups}

# Setze Berechtigungen
chown -R nasuser:nasuser /mnt/perry-nas/home
chmod -R 0777 /mnt/perry-nas/public
chmod -R 0770 /mnt/perry-nas/home

success "Dateisystem eingerichtet"

# --------------------------
# Nginx konfigurieren
# --------------------------
log "Konfiguriere Nginx..."

# Deaktiviere default site
rm -f /etc/nginx/sites-enabled/default

# Perry-NAS Web-Konfiguration
cat > /etc/nginx/sites-available/perry-nas << 'EOF'
server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    
    root /var/www/html;
    index index.html index.htm;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Main site
    location / {
        try_files $uri $uri/ =404;
    }
    
    # API endpoints
    location /api/ {
        alias /var/www/html/api/;
        include fastcgi_params;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
    
    # Block access to sensitive files
    location ~ /\. {
        deny all;
    }
    
    location ~ /(config|backups) {
        deny all;
    }
}
EOF

# Aktiviere Site
ln -sf /etc/nginx/sites-available/perry-nas /etc/nginx/sites-enabled/

success "Nginx konfiguriert"

# --------------------------
# CGI für API einrichten
# --------------------------
log "Richte CGI für API ein..."

# Installiere fcgiwrap für CGI-Support
apt install -y fcgiwrap

# Erstelle API-Verzeichnis
mkdir -p /var/www/html/api
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html/api

success "CGI eingerichtet"

# --------------------------
# System-Scripts erstellen
# --------------------------
log "Erstelle System-Scripts..."

# System-Info Script
cat > /usr/local/bin/nas-system-info << 'EOF'
#!/bin/bash
case "$1" in
    "status")
        cat << STATUS
{
    "hostname": "$(hostname)",
    "uptime": "$(uptime -p | sed 's/up //')",
    "load": "$(cat /proc/loadavg | awk '{print $1\", \"$2\", \"$3}')",
    "memory": "$(free -h | grep Mem | awk '{print $3 \"/\" $2}')",
    "storage": "$(df -h /mnt/perry-nas 2>/dev/null | tail -1 | awk '{print $3 \"/\" $2 \" (\" $5 \")\"}' || echo 'N/A')",
    "temperature": "$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 || echo 'N/A')",
    "time": "$(date '+%Y-%m-%d %H:%M:%S')"
}
STATUS
        ;;
    "services")
        echo "{\"smbd\": \"$(systemctl is-active smbd 2>/dev/null || echo 'inactive')\", \"nginx\": \"$(systemctl is-active nginx)\"}"
        ;;
    "updates")
        apt update >/dev/null 2>&1
        UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
        echo $UPDATES
        ;;
    *)
        echo "{\"error\": \"Unknown command\"}"
        ;;
esac
EOF

# System-Action Script
cat > /usr/local/bin/nas-system-action << 'EOF'
#!/bin/bash
ACTION=$1

case $ACTION in
    "restart-services")
        systemctl restart smbd nginx
        echo "Dienste neu gestartet"
        ;;
    "check-updates")
        apt update
        UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
        echo "Verfügbare Updates: $UPDATES"
        ;;
    "safe-reboot")
        echo "System wird in 1 Minute neu gestartet..."
        shutdown -r +1
        ;;
    "safe-shutdown")
        echo "System wird in 1 Minute heruntergefahren..."
        shutdown -h +1
        ;;
    "test-samba")
        smbstatus && echo "Samba läuft korrekt"
        ;;
    "test-web")
        curl -s http://localhost > /dev/null && echo "Webserver läuft korrekt"
        ;;
    *)
        echo "Unbekannte Aktion: $ACTION"
        exit 1
        ;;
esac
EOF

# Backup Script
cat > /usr/local/bin/nas-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/perry-nas/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/nas-backup-$DATE.tar.gz"
LOG_FILE="/var/log/nas-backup.log"

echo "$(date): Starting backup" >> $LOG_FILE

mkdir -p $BACKUP_DIR

echo "Starte Backup: $BACKUP_FILE"

# Wichtige Konfigurationsdateien sichern
tar -czf $BACKUP_FILE \
    /etc/samba/smb.conf \
    /etc/nginx/sites-available/perry-nas \
    /etc/fstab \
    /etc/hostname \
    /etc/hosts \
    /usr/local/bin/nas-* 2>/dev/null

if [ $? -eq 0 ]; then
    SIZE=$(du -h $BACKUP_FILE | cut -f1)
    echo "Backup erfolgreich: $BACKUP_FILE ($SIZE)"
    echo "$(date): Backup successful - $BACKUP_FILE ($SIZE)" >> $LOG_FILE
    
    # Alte Backups löschen (älter als 7 Tage)
    find $BACKUP_DIR -name "nas-backup-*.tar.gz" -mtime +7 -delete
else
    echo "Backup fehlgeschlagen"
    echo "$(date): Backup failed" >> $LOG_FILE
    exit 1
fi
EOF

# Scripts ausführbar machen
chmod +x /usr/local/bin/nas-*
success "System-Scripts erstellt"

# --------------------------
# API-Endpoints erstellen
# --------------------------
log "Erstelle API-Endpoints..."

# System-Info API
cat > /var/www/html/api/system-info << 'EOF'
#!/bin/bash
echo "Content-type: application/json"
echo ""

# Query-String parsen
if [ "$REQUEST_METHOD" = "GET" ]; then
    ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')
else
    read -n $CONTENT_LENGTH POST_DATA
    ACTION=$(echo "$POST_DATA" | sed -n 's/.*action=\([^&]*\).*/\1/p')
fi

case "$ACTION" in
    "status")
        /usr/local/bin/nas-system-info status
        ;;
    "services")
        /usr/local/bin/nas-system-info services
        ;;
    "updates")
        /usr/local/bin/nas-system-info updates
        ;;
    *)
        echo '{"error": "Invalid action"}'
        ;;
esac
EOF

# System-Action API
cat > /var/www/html/api/system-action << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""

# Query-String parsen
if [ "$REQUEST_METHOD" = "GET" ]; then
    ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')
else
    read -n $CONTENT_LENGTH POST_DATA
    ACTION=$(echo "$POST_DATA" | sed -n 's/.*action=\([^&]*\).*/\1/p')
fi

# Log-Aktion
echo "$(date): Action $ACTION from $REMOTE_ADDR" >> /var/log/nas-admin.log

# Nur sichere Aktionen erlauben
case "$ACTION" in
    "restart-services"|"check-updates"|"safe-reboot"|"safe-shutdown"|"test-samba"|"test-web")
        /usr/local/bin/nas-system-action "$ACTION"
        ;;
    *)
        echo "Unauthorized action: $ACTION"
        exit 1
        ;;
esac
EOF

# Backup API
cat > /var/www/html/api/backup << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""

# Log-Aktion
echo "$(date): Backup started from $REMOTE_ADDR" >> /var/log/nas-admin.log

/usr/local/bin/nas-backup
EOF

# API-Scripts ausführbar machen
chmod +x /var/www/html/api/*
chown www-data:www-data /var/www/html/api/*

success "API-Endpoints erstellt"

# --------------------------
# Web-Interface erstellen
# --------------------------
log "Erstelle Web-Interface..."

cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Perry-NAS Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        :root {
            --primary: #6366f1;
            --primary-dark: #4338ca;
            --secondary: #64748b;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
            --dark: #1e293b;
            --light: #f8fafc;
            --border: #e2e8f0;
        }
        
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: var(--dark);
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
            color: white;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            font-weight: 700;
        }
        
        .header p {
            opacity: 0.9;
            font-size: 1.1rem;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .card {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .card h2 {
            color: var(--primary-dark);
            margin-bottom: 16px;
            font-size: 1.25rem;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .stat-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }
        
        .stat-item {
            background: var(--light);
            padding: 12px;
            border-radius: 8px;
            border-left: 4px solid var(--primary);
        }
        
        .stat-value {
            font-size: 1.1rem;
            font-weight: 600;
            color: var(--primary-dark);
        }
        
        .stat-label {
            font-size: 0.875rem;
            color: var(--secondary);
            margin-top: 4px;
        }
        
        .btn {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 10px 16px;
            border: none;
            border-radius: 8px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
            text-decoration: none;
            font-size: 0.875rem;
        }
        
        .btn-primary {
            background: var(--primary);
            color: white;
        }
        
        .btn-primary:hover {
            background: var(--primary-dark);
            transform: translateY(-1px);
        }
        
        .btn-warning {
            background: var(--warning);
            color: white;
        }
        
        .btn-danger {
            background: var(--danger);
            color: white;
        }
        
        .btn-group {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
        }
        
        .service-status {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid var(--border);
        }
        
        .service-status:last-child {
            border-bottom: none;
        }
        
        .status-badge {
            padding: 4px 8px;
            border-radius: 6px;
            font-size: 0.75rem;
            font-weight: 500;
        }
        
        .status-active {
            background: #dcfce7;
            color: #166534;
        }
        
        .status-inactive {
            background: #fecaca;
            color: #991b1b;
        }
        
        .log-output {
            background: var(--dark);
            color: #00ff00;
            padding: 16px;
            border-radius: 8px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.875rem;
            height: 200px;
            overflow-y: auto;
            margin-top: 12px;
        }
        
        .refresh-btn {
            background: none;
            border: none;
            color: var(--primary);
            cursor: pointer;
            padding: 4px;
            border-radius: 4px;
        }
        
        .refresh-btn:hover {
            background: rgba(99, 102, 241, 0.1);
        }
        
        .notification {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 16px;
            border-radius: 8px;
            color: white;
            z-index: 1000;
            animation: slideIn 0.3s ease;
        }
        
        .notification.success {
            background: var(--success);
        }
        
        .notification.error {
            background: var(--danger);
        }
        
        @keyframes slideIn {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        
        .footer {
            text-align: center;
            margin-top: 30px;
            color: white;
            opacity: 0.8;
            font-size: 0.875rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🍐 Perry-NAS Dashboard</h1>
            <p>Einfache Systemüberwachung & Verwaltung</p>
        </header>
        
        <div class="grid">
            <!-- System Status -->
            <div class="card">
                <h2>
                    📊 System Status
                    <button class="refresh-btn" onclick="refreshStatus()">🔄</button>
                </h2>
                <div class="stat-grid" id="system-status">
                    <div class="stat-item">
                        <div class="stat-value" id="hostname">--</div>
                        <div class="stat-label">Hostname</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="uptime">--</div>
                        <div class="stat-label">Laufzeit</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="load">--</div>
                        <div class="stat-label">CPU Last</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="memory">--</div>
                        <div class="stat-label">Arbeitsspeicher</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="storage">--</div>
                        <div class="stat-label">Speicher</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="temperature">--</div>
                        <div class="stat-label">Temperatur</div>
                    </div>
                </div>
            </div>
            
            <!-- Dienst Status -->
            <div class="card">
                <h2>🔧 Dienste</h2>
                <div id="service-status">
                    <div class="service-status">
                        <span>Samba Filesharing</span>
                        <span class="status-badge status-active" id="service-smbd">Lädt...</span>
                    </div>
                    <div class="service-status">
                        <span>Web Server</span>
                        <span class="status-badge status-active" id="service-nginx">Lädt...</span>
                    </div>
                </div>
            </div>
            
            <!-- Schnellaktionen -->
            <div class="card">
                <h2>⚡ Schnellaktionen</h2>
                <div class="btn-group">
                    <button class="btn btn-primary" onclick="executeAction('restart-services')">
                        🔄 Dienste neustarten
                    </button>
                    <button class="btn btn-primary" onclick="executeAction('check-updates')">
                        📦 Updates prüfen
                    </button>
                    <button class="btn btn-primary" onclick="executeAction('test-samba')">
                        🔍 Samba testen
                    </button>
                    <button class="btn btn-primary" onclick="executeAction('test-web')">
                        🌐 Web testen
                    </button>
                    <button class="btn btn-warning" onclick="showBackup()">
                        💾 Backup erstellen
                    </button>
                </div>
                
                <div style="margin-top: 16px;">
                    <h3 style="font-size: 1rem; margin-bottom: 8px;">Systemaktionen</h3>
                    <div class="btn-group">
                        <button class="btn btn-warning" onclick="confirmAction('safe-reboot', 'System neustarten?')">
                            🔄 Neustart
                        </button>
                        <button class="btn btn-danger" onclick="confirmAction('safe-shutdown', 'System herunterfahren?')">
                            ⏻ Herunterfahren
                        </button>
                    </div>
                </div>
            </div>
            
            <!-- Backup Bereich -->
            <div class="card" id="backup-section" style="display: none;">
                <h2>💾 System Backup</h2>
                <p style="margin-bottom: 12px; color: var(--secondary);">
                    Erstellt ein Backup der Systemkonfiguration und Benutzerdaten.
                </p>
                <button class="btn btn-primary" onclick="startBackup()">
                    🔄 Backup starten
                </button>
                <div class="log-output" id="backup-output"></div>
            </div>
            
            <!-- System Information -->
            <div class="card">
                <h2>ℹ️ System Information</h2>
                <div style="margin-bottom: 12px;">
                    <div style="font-size: 0.875rem; color: var(--secondary); margin-bottom: 4px;">SSH Zugang:</div>
                    <code style="background: var(--light); padding: 4px 8px; border-radius: 4px; font-size: 0.875rem;">
                        ssh ramon@<span id="ip-address">IP-ADRESSE</span>
                    </code>
                </div>
                <div style="margin-bottom: 12px;">
                    <div style="font-size: 0.875rem; color: var(--secondary); margin-bottom: 4px;">Samba Zugang:</div>
                    <code style="background: var(--light); padding: 4px 8px; border-radius: 4px; font-size: 0.875rem;">
                        //<span id="samba-ip">IP-ADRESSE</span>/public
                    </code>
                </div>
                <div>
                    <div style="font-size: 0.875rem; color: var(--secondary); margin-bottom: 4px;">Verfügbare Updates:</div>
                    <div id="update-count">Wird geladen...</div>
                </div>
            </div>
        </div>
        
        <footer class="footer">
            <p>Perry-NAS • Debian Trixie • $(date +%Y) • Sicher & Einfach</p>
        </footer>
    </div>

    <script>
        // Systemstatus abrufen
        async function refreshStatus() {
            try {
                const response = await fetch('/api/system-info?action=status');
                const data = await response.json();
                
                document.getElementById('hostname').textContent = data.hostname;
                document.getElementById('uptime').textContent = data.uptime;
                document.getElementById('load').textContent = data.load;
                document.getElementById('memory').textContent = data.memory;
                document.getElementById('storage').textContent = data.storage;
                document.getElementById('temperature').textContent = data.temperature;
                
                // IP-Adresse anzeigen
                const hostname = window.location.hostname;
                document.getElementById('ip-address').textContent = hostname;
                document.getElementById('samba-ip').textContent = hostname;
                
            } catch (error) {
                console.error('Fehler beim Laden des Status:', error);
            }
            
            // Dienststatus abrufen
            try {
                const response = await fetch('/api/system-info?action=services');
                const data = await response.json();
                
                updateServiceStatus('service-smbd', data.smbd);
                updateServiceStatus('service-nginx', data.nginx);
                
            } catch (error) {
                console.error('Fehler beim Laden der Dienste:', error);
            }
            
            // Updates abrufen
            try {
                const response = await fetch('/api/system-info?action=updates');
                const count = await response.text();
                document.getElementById('update-count').textContent = 
                    count + ' verfügbare Updates';
            } catch (error) {
                console.error('Fehler beim Laden der Updates:', error);
            }
        }
        
        function updateServiceStatus(elementId, status) {
            const element = document.getElementById(elementId);
            element.textContent = status === 'active' ? 'Aktiv' : 'Inaktiv';
            element.className = `status-badge ${status === 'active' ? 'status-active' : 'status-inactive'}`;
        }
        
        // Aktionen ausführen
        async function executeAction(action) {
            showNotification('Aktion wird ausgeführt...', 'success');
            
            try {
                const response = await fetch(`/api/system-action?action=${action}`);
                const result = await response.text();
                showNotification('Aktion erfolgreich', 'success');
                console.log('Ergebnis:', result);
                
                // Status nach Aktionen aktualisieren
                if (action === 'restart-services') {
                    setTimeout(refreshStatus, 2000);
                }
            } catch (error) {
                showNotification('Fehler bei der Aktion', 'error');
                console.error('Fehler:', error);
            }
        }
        
        // Backup-Funktionen
        function showBackup() {
            document.getElementById('backup-section').style.display = 'block';
        }
        
        async function startBackup() {
            const output = document.getElementById('backup-output');
            output.textContent = 'Backup wird gestartet...\n';
            
            try {
                const response = await fetch('/api/backup');
                const result = await response.text();
                output.textContent += result;
                showNotification('Backup erfolgreich gestartet', 'success');
            } catch (error) {
                output.textContent += 'Fehler beim Backup: ' + error;
                showNotification('Backup fehlgeschlagen', 'error');
            }
        }
        
        // Bestätigung für kritische Aktionen
        function confirmAction(action, message) {
            if (confirm(message + '\n\nDas System wird eine Warnung anzeigen und die Aktion in 1 Minute ausführen.')) {
                executeAction(action);
            }
        }
        
        // Notification System
        function showNotification(message, type) {
            const notification = document.createElement('div');
            notification.className = `notification ${type}`;
            notification.textContent = message;
            document.body.appendChild(notification);
            
            setTimeout(() => {
                notification.remove();
            }, 3000);
        }
        
        // Automatische Aktualisierung
        setInterval(refreshStatus, 30000);
        
        // Initialisierung
        document.addEventListener('DOMContentLoaded', function() {
            refreshStatus();
        });
    </script>
</body>
</html>
EOF

# Setze Berechtigungen für Web-Interface
chown www-data:www-data /var/www/html/index.html
chmod 644 /var/www/html/index.html

success "Web-Interface erstellt"

# --------------------------
# Sudo-Berechtigungen
# --------------------------
log "Richte Sudo-Berechtigungen ein..."

cat > /etc/sudoers.d/perry-nas << 'EOF'
# Perry-NAS Sudo-Berechtigungen
www-data ALL=(root) NOPASSWD: /usr/local/bin/nas-system-action
www-data ALL=(root) NOPASSWD: /usr/local/bin/nas-backup
ramon ALL=(root) NOPASSWD: /usr/local/bin/nas-*
EOF

chmod 440 /etc/sudoers.d/perry-nas

success "Sudo-Berechtigungen konfiguriert"

# --------------------------
# Firewall konfigurieren
# --------------------------
log "Konfiguriere Firewall..."

# UFW zurücksetzen
ufw --force reset

# Standard-Regeln
ufw default deny incoming
ufw default allow outgoing

# Erlaube wichtige Ports
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 445/tcp comment 'Samba'
ufw allow 139/tcp comment 'Samba NetBIOS'

# Aktiviere UFW
ufw --force enable

success "Firewall konfiguriert"

# --------------------------
# Systemd Services
# --------------------------
log "Starte und aktiviere Services..."

# Services neu laden
systemctl daemon-reload

# Aktiviere und starte Services
systemctl enable nginx smbd fcgiwrap
systemctl start nginx smbd fcgiwrap

# Prüfe Service-Status
if systemctl is-active --quiet nginx; then
    success "Nginx läuft"
else
    error "Nginx konnte nicht gestartet werden"
fi

if systemctl is-active --quiet smbd; then
    success "Samba läuft"
else
    error "Samba konnte nicht gestartet werden"
fi

success "Services gestartet"

# --------------------------
# Logging einrichten
# --------------------------
log "Richte Logging ein..."

touch /var/log/nas-admin.log
touch /var/log/nas-backup.log
chown www-data:www-data /var/log/nas-*.log
chmod 644 /var/log/nas-*.log

# Logrotate für NAS Logs
cat > /etc/logrotate.d/perry-nas << 'EOF'
/var/log/nas-*.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

success "Logging eingerichtet"

# --------------------------
# Abschluss & Informationen
# --------------------------
IP_ADDRESS=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#      PERRY-NAS SETUP ABGESCHLOSSEN!      #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""
echo -e "${GREEN}🎉 Perry-NAS wurde erfolgreich auf Debian Trixie installiert!${NC}"
echo ""
echo -e "${CYAN}🔗 ZUGANGSDATEN:${NC}"
echo -e "  🌐 Web Interface: http://${IP_ADDRESS}/"
echo -e "  🔐 SSH Zugang: ssh ramon@${IP_ADDRESS}"
echo -e "  📁 Samba Public: //${IP_ADDRESS}/public"
echo -e "  🔒 Samba Home: //${IP_ADDRESS}/home (User: nasuser, Pass: nasuser123)"
echo ""
echo -e "${CYAN}⚡ FUNKTIONEN:${NC}"
echo -e "  📊 Echtzeit System Monitoring"
echo -e "  🔄 Dienste verwalten"
echo -e "  💾 Backup-System"
echo -e "  🛡️  Integrierte Firewall"
echo -e "  📦 Update-Verwaltung"
echo ""
echo -e "${YELLOW}🔧 SYSTEMINFORMATIONEN:${NC}"
echo -e "  🖥️  Hostname: ${HOSTNAME}"
echo -e "  📡 IP-Adresse: ${IP_ADDRESS}"
echo -e "  🐧 Distribution: Debian Trixie"
echo ""
echo -e "${GREEN}📋 NÄCHSTE SCHRITTE:${NC}"
echo -e "  1. Web Interface öffnen: http://${IP_ADDRESS}/"
echo -e "  2. Samba Shares einrichten"
echo -e "  3. Regelmäßige Backups konfigurieren"
echo -e "  4. SSH Keys für sicheren Zugang einrichten"
echo ""
echo -e "${GREEN}🍐 Perry-NAS ist bereit! Viel Spaß mit deinem neuen NAS System!${NC}"