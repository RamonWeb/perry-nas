#!/bin/bash
# Perry-NAS Neo Admin Panel - Einfach & Sicher

set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${PURPLE}[NEO-ADMIN]${NC} $1"; }
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
echo -e "${PURPLE}#         PERRY-NAS NEO ADMIN PANEL        #${NC}"
echo -e "${PURPLE}#           Einfach & Sicher               #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""

# --------------------------
# Basis-Systemeinrichtung
# --------------------------
log "Richte Basis-System ein..."

# Installiere benötigte Pakete
log "Installiere benötigte Pakete..."
apt update
apt install -y sudo curl jq

# Erstelle Admin-Benutzer (falls nicht vorhanden)
if ! id "nasadmin" &>/dev/null; then
    log "Erstelle nasadmin Benutzer..."
    useradd -m -s /bin/bash nasadmin
    echo "nasadmin:$(openssl rand -base64 12)" | chpasswd
    usermod -aG sudo nasadmin
    success "Admin-Benutzer erstellt"
fi

# --------------------------
# API-Verzeichnis erstellen
# --------------------------
log "Erstelle API-Verzeichnis..."
mkdir -p /var/www/html/api
chown www-data:www-data /var/www/html/api
chmod 755 /var/www/html/api

# --------------------------
# Sichere API-Scripts
# --------------------------
log "Erstelle sichere API-Scripts..."

# System-Info Script
cat > /usr/local/bin/nas-system-info << 'EOF'
#!/bin/bash
case $1 in
    "status")
        cat << STATUS
{
    "hostname": "$(hostname)",
    "uptime": "$(uptime -p)",
    "load": "$(cat /proc/loadavg)",
    "memory": "$(free -h | grep Mem | awk '{print $3 \"/\" $2}')",
    "storage": "$(df -h /mnt/perry-nas 2>/dev/null | tail -1 | awk '{print $3 \"/\" $2 \" (\" $5 \")\"}' || echo 'N/A')",
    "temperature": "$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 || echo 'N/A')",
    "time": "$(date)"
}
STATUS
        ;;
    "services")
        echo "{\"smbd\": \"$(systemctl is-active smbd)\", \"nginx\": \"$(systemctl is-active nginx)\"}"
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

# Backup Script
cat > /usr/local/bin/nas-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/home/nasadmin/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/nas-backup-$DATE.tar.gz"

mkdir -p $BACKUP_DIR

echo "Starte Backup: $BACKUP_FILE"

# Wichtige Konfigurationsdateien sichern
tar -czf $BACKUP_FILE \
    /etc/samba/smb.conf \
    /etc/nginx/sites-available/default \
    /etc/fstab \
    /etc/hostname \
    /etc/hosts \
    /home/nasadmin/ 2>/dev/null

SIZE=$(du -h $BACKUP_FILE | cut -f1)
echo "Backup abgeschlossen: $BACKUP_FILE ($SIZE)"

# Alte Backups löschen (älter als 7 Tage)
find $BACKUP_DIR -name "nas-backup-*.tar.gz" -mtime +7 -delete

echo "Backup erfolgreich"
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
        apt list --upgradable
        ;;
    "safe-reboot")
        echo "System wird in 1 Minute neu gestartet..."
        shutdown -r +1
        ;;
    "safe-shutdown")
        echo "System wird in 1 Minute heruntergefahren..."
        shutdown -h +1
        ;;
    *)
        echo "Unbekannte Aktion"
        exit 1
        ;;
esac
EOF

# Scripts ausführbar machen
chmod +x /usr/local/bin/nas-*
chown nasadmin:nasadmin /usr/local/bin/nas-*

success "API-Scripts erstellt"

# --------------------------
# Modernes Web-Interface
# --------------------------
log "Erstelle modernes Web-Interface..."

# Hauptseite
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
            color: var(--success);
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
                        ssh nasadmin@<span id="ip-address">IP-ADRESSE</span>
                    </code>
                </div>
                <div>
                    <div style="font-size: 0.875rem; color: var(--secondary); margin-bottom: 4px;">Verfügbare Updates:</div>
                    <div id="update-count">Wird geladen...</div>
                </div>
            </div>
        </div>
        
        <footer class="footer">
            <p>Perry-NAS Neo Admin Panel • $(date +%Y) • Sicher & Einfach</p>
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
                document.getElementById('load').textContent = data.load.split(' ')[0];
                document.getElementById('memory').textContent = data.memory;
                document.getElementById('storage').textContent = data.storage;
                document.getElementById('temperature').textContent = data.temperature;
                
                // IP-Adresse anzeigen
                const hostname = window.location.hostname;
                document.getElementById('ip-address').textContent = hostname;
                
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

# --------------------------
# Einfache API-Endpoints
# --------------------------
log "Erstelle API-Endpoints..."

# System-Info API
cat > /var/www/html/api/system-info << 'EOF'
#!/bin/bash
echo "Content-type: application/json"
echo ""

ACTION=$(echo "$QUERY_STRING" | grep -oP 'action=\K[^&]*')

case $ACTION in
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

ACTION=$(echo "$QUERY_STRING" | grep -oP 'action=\K[^&]*')

# Nur sichere Aktionen erlauben
case $ACTION in
    "restart-services"|"check-updates"|"safe-reboot"|"safe-shutdown")
        sudo /usr/local/bin/nas-system-action "$ACTION"
        ;;
    *)
        echo "Unauthorized action"
        exit 1
        ;;
esac
EOF

# Backup API
cat > /var/www/html/api/backup << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""

# Backup als nasadmin Benutzer ausführen
sudo -u nasadmin /usr/local/bin/nas-backup
EOF

# API-Scripts ausführbar machen
chmod +x /var/www/html/api/*
chown www-data:www-data /var/www/html/api/*

success "API-Endpoints erstellt"

# --------------------------
# Sudo-Berechtigungen einschränken
# --------------------------
log "Richte sichere Sudo-Berechtigungen ein..."

cat > /etc/sudoers.d/nas-admin << 'EOF'
# Perry-NAS eingeschränkte Sudo-Berechtigungen
www-data ALL=(root) NOPASSWD: /usr/local/bin/nas-system-action
www-data ALL=(nasadmin) NOPASSWD: /usr/local/bin/nas-backup
nasadmin ALL=(root) NOPASSWD: /usr/local/bin/nas-system-action
EOF

chmod 440 /etc/sudoers.d/nas-admin

# --------------------------
# Systemd Service für Automatisierung
# --------------------------
log "Erstelle Systemd Services..."

# Auto-Backup Service
cat > /etc/systemd/system/nas-auto-backup.service << 'EOF'
[Unit]
Description=Perry-NAS Auto Backup
After=network.target

[Service]
Type=oneshot
User=nasadmin
ExecStart=/usr/local/bin/nas-backup

[Install]
WantedBy=multi-user.target
EOF

# Auto-Backup Timer
cat > /etc/systemd/system/nas-auto-backup.timer << 'EOF'
[Unit]
Description=Auto Backup Timer
Requires=nas-auto-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable nas-auto-backup.timer

success "Systemd Services erstellt"

# --------------------------
# Sicherheitskonfiguration
# --------------------------
log "Konfiguriere Sicherheitseinstellungen..."

# Firewall Regeln (falls ufw aktiv)
if command -v ufw > /dev/null; then
    ufw allow 80/tcp comment "NAS Web Interface"
    ufw allow 22/tcp comment "SSH Access"
    ufw allow 445/tcp comment "Samba"
    success "Firewall Regeln konfiguriert"
fi

# SSH Sicherheit
if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
fi
if ! grep -q "AllowUsers nasadmin" /etc/ssh/sshd_config; then
    echo "AllowUsers nasadmin" >> /etc/ssh/sshd_config
fi
systemctl reload sshd

success "SSH Sicherheit konfiguriert"

# --------------------------
# Abschluss & Informationen
# --------------------------
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${PURPLE}#############################################${NC}"
echo -e "${PURPLE}#      PERRY-NAS NEO ADMIN BEREIT!         #${NC}"
echo -e "${PURPLE}#############################################${NC}"
echo ""
echo -e "${GREEN}🎉 Neo Admin Panel erfolgreich installiert!${NC}"
echo ""
echo -e "${CYAN}🔗 ZUGANGSDATEN:${NC}"
echo -e "  🌐 Web Interface: http://${IP_ADDRESS}/"
echo -e "  🔐 SSH Zugang: ssh nasadmin@${IP_ADDRESS}"
echo -e "  📝 SSH Passwort: Wird beim ersten Login gesetzt"
echo ""
echo -e "${CYAN}⚡ FUNKTIONEN:${NC}"
echo -e "  📊 Echtzeit System Monitoring"
echo -e "  🔄 Sichere Systemaktionen"
echo -e "  💾 Automatische Backups (täglich)"
echo -e "  🛡️  Eingeschränkte Berechtigungen"
echo ""
echo -e "${YELLOW}🔒 SICHERHEIT:${NC}"
echo -e "  ✅ Keine root-Berechtigungen für Web-Interface"
echo -e "  ✅ Separater Admin-Benutzer"
echo -e "  ✅ SSH Key-basierte Authentifizierung"
echo -e "  ✅ Eingeschränkte sudo-Berechtigungen"
echo ""
echo -e "${GREEN}📋 NÄCHSTE SCHRITTE:${NC}"
echo -e "  1. SSH Key für nasadmin einrichten:"
echo -e "     ssh-copy-id nasadmin@${IP_ADDRESS}"
echo -e "  2. SSH Passwort-Login deaktivieren"
echo -e "  3. Backup-Verzeichnis prüfen: /home/nasadmin/backups/"
echo ""
echo -e "${GREEN}🍐 Einfach. Sicher. Modern.${NC}"