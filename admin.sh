#!/bin/bash
# perry-nas-multi-ssh-setup.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[SSH-SETUP]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Root check
if [ "$EUID" -ne 0 ]; then
    error "Bitte als root ausführen: sudo $0"
    exit 1
fi

echo ""
echo -e "${GREEN}Perry-NAS Multi-Client SSH Setup${NC}"
echo "======================================"

# --------------------------
# SSH Server Konfiguration
# --------------------------
log "Konfiguriere SSH Server für Multi-Client Zugriff..."

SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Backup der originalen Config
cp $SSH_CONFIG $BACKUP_FILE
log "Backup erstellt: $BACKUP_FILE"

# SSH Konfiguration für Multi-Client
cat > /tmp/sshd_config_update << 'EOF'
# Perry-NAS Multi-Client SSH Configuration
Protocol 2
Port 22
AddressFamily inet

# Security Settings
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Authentication
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2
HostbasedAuthentication no
IgnoreUserKnownHosts no
IgnoreRhosts yes

# Password Authentication (nur als Fallback - später deaktivieren)
PasswordAuthentication yes
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# Users and Access
AllowUsers ramon
DenyUsers root

# Crypto Settings
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Other Settings
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
UsePAM yes
AllowTcpForwarding no
PermitTunnel no
AllowAgentForwarding no
EOF

# Konfiguration anwenden
cat /tmp/sshd_config_update >> $SSH_CONFIG
rm /tmp/sshd_config_update

# SSH Directory für Benutzer vorbereiten
log "Richte SSH Verzeichnis ein..."
sudo -u ramon mkdir -p /home/ramon/.ssh
touch /home/ramon/.ssh/authorized_keys
chmod 700 /home/ramon/.ssh
chmod 600 /home/ramon/.ssh/authorized_keys
chown -R ramon:ramon /home/ramon/.ssh

# --------------------------
# Management Scripts erstellen
# --------------------------
log "Erstelle Management Scripts..."

# Script zum Hinzufügen von SSH Keys
cat > /usr/local/bin/nas-add-ssh-key << 'EOF'
#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Verwendung: nas-add-ssh-key 'ssh-public-key'"
    echo "          nas-add-ssh-key -f keyfile.pub"
    exit 1
fi

KEY="$1"
KEY_FILE="/home/ramon/.ssh/authorized_keys"
BACKUP_FILE="${KEY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Backup erstellen
cp $KEY_FILE $BACKUP_FILE

if [ "$KEY" = "-f" ] && [ -n "$2" ]; then
    # Key aus Datei hinzufügen
    if [ -f "$2" ]; then
        cat "$2" >> $KEY_FILE
        echo "✅ Key aus Datei $2 hinzugefügt"
        echo "📋 Backup: $BACKUP_FILE"
    else
        echo "❌ Datei $2 nicht gefunden"
        exit 1
    fi
else
    # Key direkt hinzufügen
    echo "$KEY" >> $KEY_FILE
    echo "✅ Key hinzugefügt"
    echo "📋 Backup: $BACKUP_FILE"
fi

# Duplikate entfernen
sort $KEY_FILE | uniq > ${KEY_FILE}.tmp
mv ${KEY_FILE}.tmp $KEY_FILE

# Berechtigungen setzen
chmod 600 $KEY_FILE
chown ramon:ramon $KEY_FILE

echo "🔑 Aktuelle Keys:"
wc -l $KEY_FILE
EOF

# Script zum Entfernen von SSH Keys
cat > /usr/local/bin/nas-remove-ssh-key << 'EOF'
#!/bin/bash

KEY_FILE="/home/ramon/.ssh/authorized_keys"
BACKUP_FILE="${KEY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

if [ $# -eq 0 ]; then
    echo "Verwendung: nas-remove-ssh-key 'key-comment'"
    echo "          nas-remove-ssh-key --list"
    exit 1
fi

if [ "$1" = "--list" ]; then
    echo "🔑 Gespeicherte SSH Keys:"
    nl $KEY_FILE
    exit 0
fi

PATTERN="$1"

# Backup erstellen
cp $KEY_FILE $BACKUP_FILE

# Key entfernen
grep -v "$PATTERN" $KEY_FILE > ${KEY_FILE}.tmp
mv ${KEY_FILE}.tmp $KEY_FILE

# Berechtigungen setzen
chmod 600 $KEY_FILE
chown ramon:ramon $KEY_FILE

echo "✅ Keys mit Pattern '$PATTERN' entfernt"
echo "📋 Backup: $BACKUP_FILE"
echo "🔑 Verbleibende Keys:"
wc -l $KEY_FILE
EOF

# Script zum Anzeigen der SSH Konfiguration
cat > /usr/local/bin/nas-ssh-status << 'EOF'
#!/bin/bash

echo "🔐 Perry-NAS SSH Status"
echo "======================"

echo ""
echo "📡 SSH Service Status:"
systemctl is-active ssh

echo ""
echo "🔑 Aktive SSH Keys:"
KEY_FILE="/home/ramon/.ssh/authorized_keys"
if [ -f "$KEY_FILE" ]; then
    COUNT=$(wc -l < "$KEY_FILE")
    echo "Anzahl gespeicherter Keys: $COUNT"
    echo ""
    echo "📋 Key Kommentare:"
    grep -o ' [^ ]*@[^ ]*' "$KEY_FILE" | sort | uniq | nl
else
    echo "❌ Keine SSH Keys konfiguriert"
fi

echo ""
echo "🌐 Verbindungen:"
netstat -tln | grep :22

echo ""
echo "📊 Letzte Login Versuche:"
tail -10 /var/log/auth.log | grep sshd
EOF

# Scripts ausführbar machen
chmod +x /usr/local/bin/nas-*-ssh-*
chown root:root /usr/local/bin/nas-*-ssh-*

# --------------------------
# Web-Interface für SSH Management
# --------------------------
log "Erstelle Web-Interface für SSH Management..."

cat > /var/www/html/ssh-management.html << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH Key Management - Perry-NAS</title>
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
            max-width: 1000px;
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
        
        .card {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
            border: 1px solid rgba(255, 255, 255, 0.2);
            margin-bottom: 20px;
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
        
        .btn-danger {
            background: var(--danger);
            color: white;
        }
        
        .form-group {
            margin-bottom: 16px;
        }
        
        label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
        }
        
        textarea, input[type="text"] {
            width: 100%;
            padding: 12px;
            border: 2px solid var(--border);
            border-radius: 8px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.875rem;
        }
        
        textarea {
            height: 120px;
            resize: vertical;
        }
        
        .key-list {
            background: var(--light);
            padding: 16px;
            border-radius: 8px;
            margin-top: 16px;
            max-height: 300px;
            overflow-y: auto;
        }
        
        .key-item {
            padding: 8px;
            border-bottom: 1px solid var(--border);
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.75rem;
            word-break: break-all;
        }
        
        .key-item:last-child {
            border-bottom: none;
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
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🔑 SSH Key Management</h1>
            <p>Perry-NAS Multi-Client Zugriff</p>
        </header>
        
        <div class="card">
            <h2>➕ SSH Key hinzufügen</h2>
            <p>Füge einen öffentlichen SSH Key für neuen Client-Zugriff hinzu.</p>
            
            <div class="form-group">
                <label for="ssh-key">Öffentlicher SSH Key:</label>
                <textarea id="ssh-key" placeholder="ssh-ed25519 AAAA... oder ssh-rsa AAAA..."></textarea>
            </div>
            
            <div class="form-group">
                <label for="key-comment">Kommentar (optional, zur Identifikation):</label>
                <input type="text" id="key-comment" placeholder="laptop-2024 oder office-pc">
            </div>
            
            <button class="btn btn-primary" onclick="addSSHKey()">
                ➕ Key hinzufügen
            </button>
        </div>
        
        <div class="card">
            <h2>📋 Aktuelle SSH Keys</h2>
            <p>Verwaltete Keys für Client-Zugriff.</p>
            
            <button class="btn btn-primary" onclick="loadSSHKeys()">
                🔄 Liste aktualisieren
            </button>
            
            <div class="key-list" id="key-list">
                Lade Keys...
            </div>
        </div>
        
        <div class="card">
            <h2>🚪 SSH Zugangsdaten</h2>
            <div style="font-family: 'Monaco', 'Consolas', monospace; font-size: 0.875rem;">
                <p><strong>Host:</strong> <span id="nas-ip">192.168.1.100</span></p>
                <p><strong>Benutzer:</strong> ramon</p>
                <p><strong>Port:</strong> 22</p>
                <p><strong>Befehl:</strong> ssh ramon@<span id="nas-ip2">192.168.1.100</span></p>
            </div>
        </div>
    </div>

    <script>
        // IP-Adresse anzeigen
        const hostname = window.location.hostname;
        document.getElementById('nas-ip').textContent = hostname;
        document.getElementById('nas-ip2').textContent = hostname;
        
        // SSH Key hinzufügen
        async function addSSHKey() {
            const key = document.getElementById('ssh-key').value.trim();
            const comment = document.getElementById('key-comment').value.trim();
            
            if (!key) {
                showNotification('Bitte SSH Key eingeben', 'error');
                return;
            }
            
            // Kommentar zum Key hinzufügen
            let finalKey = key;
            if (comment && !key.includes(comment)) {
                finalKey = key + ' ' + comment;
            }
            
            try {
                const formData = new FormData();
                formData.append('key', finalKey);
                
                const response = await fetch('/api/ssh-add-key', {
                    method: 'POST',
                    body: formData
                });
                
                const result = await response.text();
                showNotification('SSH Key erfolgreich hinzugefügt', 'success');
                document.getElementById('ssh-key').value = '';
                document.getElementById('key-comment').value = '';
                loadSSHKeys();
            } catch (error) {
                showNotification('Fehler beim Hinzufügen des Keys', 'error');
                console.error('Fehler:', error);
            }
        }
        
        // SSH Keys laden
        async function loadSSHKeys() {
            try {
                const response = await fetch('/api/ssh-list-keys');
                const keys = await response.text();
                document.getElementById('key-list').innerHTML = keys;
            } catch (error) {
                document.getElementById('key-list').innerHTML = 'Fehler beim Laden der Keys';
                console.error('Fehler:', error);
            }
        }
        
        // Key entfernen
        async function removeSSHKey(comment) {
            if (!confirm(`Key "${comment}" wirklich entfernen?`)) {
                return;
            }
            
            try {
                const formData = new FormData();
                formData.append('comment', comment);
                
                const response = await fetch('/api/ssh-remove-key', {
                    method: 'POST',
                    body: formData
                });
                
                const result = await response.text();
                showNotification('SSH Key entfernt', 'success');
                loadSSHKeys();
            } catch (error) {
                showNotification('Fehler beim Entfernen des Keys', 'error');
                console.error('Fehler:', error);
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
        
        // Automatisch Keys laden
        document.addEventListener('DOMContentLoaded', function() {
            loadSSHKeys();
        });
    </script>
</body>
</html>
EOF

# API Endpoints für SSH Management
cat > /var/www/html/api/ssh-add-key << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""

read -n $CONTENT_LENGTH POST_DATA
KEY=$(echo "$POST_DATA" | sed -n 's/.*key=\([^&]*\).*/\1/p' | sed 's/+/ /g' | sed 's/%/\\x/g' | xargs -0 printf "%b")

if [ -z "$KEY" ]; then
    echo "Error: No key provided"
    exit 1
fi

# Key zur authorized_keys hinzufügen
echo "$KEY" >> /home/ramon/.ssh/authorized_keys

# Duplikate entfernen und sortieren
sort /home/ramon/.ssh/authorized_keys | uniq > /home/ramon/.ssh/authorized_keys.tmp
mv /home/ramon/.ssh/authorized_keys.tmp /home/ramon/.ssh/authorized_keys

# Berechtigungen setzen
chmod 600 /home/ramon/.ssh/authorized_keys
chown ramon:ramon /home/ramon/.ssh/authorized_keys

echo "Key added successfully"
EOF

cat > /var/www/html/api/ssh-list-keys << 'EOF'
#!/bin/bash
echo "Content-type: text/html"
echo ""

KEY_FILE="/home/ramon/.ssh/authorized_keys"

if [ ! -f "$KEY_FILE" ] || [ ! -s "$KEY_FILE" ]; then
    echo "<p>Keine SSH Keys konfiguriert</p>"
    exit 0
fi

while IFS= read -r key; do
    if [ -n "$key" ]; then
        # Kommentar extrahieren
        comment=$(echo "$key" | awk '{for(i=3;i<=NF;i++) printf $i " "; print ""}' | sed 's/ $//')
        algo=$(echo "$key" | awk '{print $1}')
        fingerprint=$(echo "$key" | awk '{print $2}' | cut -c-20)...
        
        echo "<div class='key-item'>"
        echo "<strong>$algo</strong> - $fingerprint<br>"
        echo "<small>$comment</small><br>"
        echo "<button class='btn btn-danger' onclick='removeSSHKey(\"$comment\")' style='margin-top: 5px; padding: 4px 8px; font-size: 0.7rem;'>🗑️ Entfernen</button>"
        echo "</div>"
    fi
done < "$KEY_FILE"
EOF

cat > /var/www/html/api/ssh-remove-key << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""

read -n $CONTENT_LENGTH POST_DATA
COMMENT=$(echo "$POST_DATA" | sed -n 's/.*comment=\([^&]*\).*/\1/p' | sed 's/+/ /g' | sed 's/%/\\x/g' | xargs -0 printf "%b")

if [ -z "$COMMENT" ]; then
    echo "Error: No comment provided"
    exit 1
fi

KEY_FILE="/home/ramon/.ssh/authorized_keys"
BACKUP_FILE="${KEY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Backup erstellen
cp $KEY_FILE $BACKUP_FILE

# Key entfernen
grep -v "$COMMENT" $KEY_FILE > ${KEY_FILE}.tmp
mv ${KEY_FILE}.tmp $KEY_FILE

# Berechtigungen setzen
chmod 600 $KEY_FILE
chown ramon:ramon $KEY_FILE

echo "Key removed successfully"
EOF

# API Scripts ausführbar machen
chmod +x /var/www/html/api/ssh-*
chown www-data:www-data /var/www/html/api/ssh-*

# --------------------------
# SSH Service neu starten
# --------------------------
log "Starte SSH Service neu..."

# Config testen
if sshd -t; then
    systemctl reload ssh
    log "SSH Service erfolgreich neu gestartet"
else
    error "SSH Konfiguration hat Fehler - restore Backup: $BACKUP_FILE"
    exit 1
fi

# --------------------------
# Abschluss
# --------------------------
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}✅ Multi-Client SSH Setup abgeschlossen!${NC}"
echo ""
echo -e "${BLUE}🔗 ZUGANGSDATEN:${NC}"
echo -e "  🌐 SSH Management: http://${IP_ADDRESS}/ssh-management.html"
echo -e "  🔐 SSH Zugang: ssh ramon@${IP_ADDRESS}"
echo ""
echo -e "${BLUE}⚡ VERFÜGBARE BEFEHLE:${NC}"
echo -e "  📋 Keys anzeigen: nas-ssh-status"
echo -e "  ➕ Key hinzufügen: nas-add-ssh-key 'ssh-key'"
echo -e "  🗑️  Key entfernen: nas-remove-ssh-key 'comment'"
echo -e "  📜 Keys auflisten: nas-remove-ssh-key --list"
echo ""
echo -e "${YELLOW}⚠️  HINWEISE:${NC}"
echo -e "  • Passwort-Login ist aktuell noch AKTIVIERT (als Fallback)"
echo -e "  • Füge Keys über Web-Interface oder Commandline hinzu"
echo -e "  • Bei Problemen: Backup in ${BACKUP_FILE}"
echo ""
echo -e "${GREEN}🚀 Perry-NAS ist bereit für Multi-Client Zugriff!${NC}"