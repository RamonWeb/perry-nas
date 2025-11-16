#!/bin/bash
# Perry-NAS Management Tool
# Vollständiger Server Manager für Festplatten, Updates, Logs und Backups

set -e

# Farbdefinitionen
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

# Root-Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte führe dieses Tool als root aus: sudo $0"
    exit 1
fi

# Konfigurationsdatei für das Tool
CONFIG_FILE="/etc/perry-nas-manager.conf"

# Initialisiere Konfigurationsdatei falls nicht vorhanden
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
# Perry-NAS Manager Konfiguration
BACKUP_DIRS="/mnt/perry-nas"
BACKUP_DEST="/mnt/perry-nas/backups"
LOG_RETENTION_DAYS=30
DEFAULT_USER="perry"
EOF
    print_info "Neue Konfigurationsdatei erstellt: $CONFIG_FILE"
fi

# Lade Konfiguration
source "$CONFIG_FILE"

# Menüfunktionen
show_main_menu() {
    clear
    echo ""
    echo -e "${PURPLE}#############################################${NC}"
    echo -e "${PURPLE}#           PERRY-NAS MANAGER               #${NC}"
    echo -e "${PURPLE}#     Vollständiger Server Manager          #${NC}"
    echo -e "${PURPLE}#############################################${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} Festplatten Management"
    echo -e "${CYAN}2)${NC} System Updates"
    echo -e "${CYAN}3)${NC} Log Dateien ansehen"
    echo -e "${CYAN}4)${NC} Backup Einstellungen"
    echo -e "${CYAN}5)${NC} System Status"
    echo -e "${CYAN}6)${NC} System Steuerung (Reboot/Shutdown)"
    echo -e "${CYAN}7)${NC} Konfiguration bearbeiten"
    echo -e "${CYAN}0)${NC} Beenden"
    echo ""
    read -p "Wähle eine Option (0-7): " choice
    echo ""
    
    case $choice in
        1) show_disk_menu ;;
        2) show_update_menu ;;
        3) show_log_menu ;;
        4) show_backup_menu ;;
        5) show_system_status ;;
        6) show_system_control_menu ;;
        7) edit_config ;;
        0) exit 0 ;;
        *) print_error "Ungültige Option!"; sleep 2; show_main_menu ;;
    esac
}

show_disk_menu() {
    clear
    echo -e "${PURPLE}=== Festplatten Management ===${NC}"
    echo ""
    echo -e "${CYAN}a)${NC} Verfügbare Festplatten anzeigen"
    echo -e "${CYAN}b)${NC} Neue Festplatte anmelden"
    echo -e "${CYAN}c)${NC} Festplatten Freigaben anzeigen"
    echo -e "${CYAN}d)${NC} Samba Freigaben verwalten"
    echo -e "${CYAN}e)${NC} Zurück zum Hauptmenü"
    echo ""
    read -p "Wähle eine Option (a-e): " choice
    echo ""
    
    case $choice in
        a) show_available_disks ;;
        b) add_new_disk ;;
        c) show_disk_mounts ;;
        d) manage_samba_shares ;;
        e) show_main_menu ;;
        *) print_error "Ungültige Option!"; sleep 2; show_disk_menu ;;
    esac
}

show_available_disks() {
    print_info "Verfügbare Block Devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
    echo ""
    read -p "Drücke Enter zum Fortfahren..."
    show_disk_menu
}

add_new_disk() {
    print_info "Verfügbare Block Devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
    echo ""
    
    read -p "Device Name der neuen Festplatte eingeben (z.B. sdb): " DISK
    if [ -z "$DISK" ]; then
        print_error "Kein Device angegeben."
        sleep 2
        show_disk_menu
        return
    fi
    
    if [ ! -e "/dev/$DISK" ]; then
        print_error "Device /dev/$DISK existiert nicht!"
        sleep 2
        show_disk_menu
        return
    fi
    
    print_warning "ACHTUNG: Diese Festplatte wird komplett gelöscht!"
    read -p "Sind Sie sicher, dass Sie /dev/$DISK formatieren möchten? (ja/NEIN): " CONFIRM
    if [ "$CONFIRM" != "ja" ]; then
        print_error "Abbruch: Keine Bestätigung erhalten."
        sleep 2
        show_disk_menu
        return
    fi
    
    print_perry "Formatiere Festplatte /dev/$DISK..."
    
    # Unmount vorhandener Partitionen
    umount "/dev/${DISK}"* 2>/dev/null || true
    
    # Erstelle Partition
    parted "/dev/$DISK" --script mklabel gpt
    parted "/dev/$DISK" --script mkpart primary ext4 0% 100%
    
    # Formatieren
    mkfs.ext4 -F "/dev/${DISK}1"
    
    # Mountpoint erstellen
    read -p "Mountpoint eingeben (z.B. /mnt/newdisk): " MOUNTPOINT
    if [ -z "$MOUNTPOINT" ]; then
        MOUNTPOINT="/mnt/${DISK}1"
    fi
    
    mkdir -p "$MOUNTPOINT"
    
    # In fstab eintragen
    echo "/dev/${DISK}1  $MOUNTPOINT  ext4  defaults,noatime,data=writeback,nobarrier,nofail  0  2" >> /etc/fstab
    
    # Mounten
    mount "$MOUNTPOINT"
    
    # Eigentümer setzen
    chown -R $DEFAULT_USER:$DEFAULT_USER "$MOUNTPOINT"
    chmod -R 775 "$MOUNTPOINT"
    
    print_success "Festplatte /dev/$DISK erfolgreich eingerichtet!"
    print_info "Mountpoint: $MOUNTPOINT"
    sleep 3
    show_disk_menu
}

show_disk_mounts() {
    print_info "Aktuelle Mounts:"
    mount | grep -E "(ext4|ntfs|btrfs|xfs)" | grep -v tmpfs
    echo ""
    print_info "Fstab Einträge:"
    cat /etc/fstab | grep -v "^#" | grep -v "^$"
    echo ""
    read -p "Drücke Enter zum Fortfahren..."
    show_disk_menu
}

manage_samba_shares() {
    clear
    echo -e "${PURPLE}=== Samba Freigaben Management ===${NC}"
    echo ""
    echo -e "${CYAN}a)${NC} Aktuelle Freigaben anzeigen"
    echo -e "${CYAN}b)${NC} Neue Freigabe erstellen"
    echo -e "${CYAN}c)${NC} Samba neu starten"
    echo -e "${CYAN}d)${NC} Zurück zum Festplatten-Menü"
    echo ""
    read -p "Wähle eine Option (a-d): " choice
    echo ""
    
    case $choice in
        a) show_samba_shares ;;
        b) create_samba_share ;;
        c) restart_samba ;;
        d) show_disk_menu ;;
        *) print_error "Ungültige Option!"; sleep 2; manage_samba_shares ;;
    esac
}

show_samba_shares() {
    print_info "Aktuelle Samba Konfiguration:"
    cat /etc/samba/smb.conf
    echo ""
    read -p "Drücke Enter zum Fortfahren..."
    manage_samba_shares
}

create_samba_share() {
    read -p "Freigabename eingeben (z.B. MeineFreigabe): " SHARE_NAME
    read -p "Pfad zur Freigabe (z.B. /mnt/newdisk): " SHARE_PATH
    read -p "Benutzer für die Freigabe (Standard: $DEFAULT_USER): " SHARE_USER
    SHARE_USER=${SHARE_USER:-$DEFAULT_USER}
    
    if [ ! -d "$SHARE_PATH" ]; then
        print_error "Pfad $SHARE_PATH existiert nicht!"
        sleep 2
        manage_samba_shares
        return
    fi
    
    # Samba Konfiguration erweitern
    cat >> /etc/samba/smb.conf << EOF

[$SHARE_NAME]
   comment = Perry-NAS Freigabe - $SHARE_NAME
   path = $SHARE_PATH
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = $SHARE_USER
   create mask = 0775
   directory mask = 0775
   force user = $SHARE_USER
EOF
    
    print_info "Samba Freigabe '$SHARE_NAME' wurde hinzugefügt."
    print_info "Setze Passwort für Benutzer $SHARE_USER:"
    smbpasswd -a "$SHARE_USER" || print_warning "Benutzer $SHARE_USER existiert bereits."
    
    restart_samba
    show_samba_shares
}

restart_samba() {
    systemctl restart smbd
    systemctl restart nmbd
    if systemctl is-active --quiet smbd; then
        print_success "Samba Dienste erfolgreich neu gestartet."
    else
        print_error "Fehler beim Neustart von Samba!"
    fi
    sleep 2
}

show_update_menu() {
    clear
    echo -e "${PURPLE}=== System Updates ===${NC}"
    echo ""
    echo -e "${CYAN}a)${NC} Updates anzeigen"
    echo -e "${CYAN}b)${NC} System aktualisieren"
    echo -e "${CYAN}c)${NC} Sicherheits-Updates installieren"
    echo -e "${CYAN}d)${NC} Zurück zum Hauptmenü"
    echo ""
    read -p "Wähle eine Option (a-d): " choice
    echo ""
    
    case $choice in
        a) show_updates ;;
        b) update_system ;;
        c) update_security ;;
        d) show_main_menu ;;
        *) print_error "Ungültige Option!"; sleep 2; show_update_menu ;;
    esac
}

show_updates() {
    print_info "Prüfe auf verfügbare Updates..."
    apt update
    print_info "Verfügbare Updates:"
    apt list --upgradable 2>/dev/null | grep -v "Listing..." || echo "Keine Updates verfügbar."
    echo ""
    read -p "Drücke Enter zum Fortfahren..."
    show_update_menu
}

update_system() {
    print_perry "Starte Systemaktualisierung..."
    apt update
    apt full-upgrade -y
    apt autoremove -y
    print_success "System erfolgreich aktualisiert!"
    sleep 3
    show_update_menu
}

update_security() {
    print_perry "Installiere Sicherheits-Updates..."
    apt update
    apt upgrade -y --only-upgrade -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    print_success "Sicherheits-Updates installiert!"
    sleep 3
    show_update_menu
}

show_log_menu() {
    clear
    echo -e "${PURPLE}=== Log Dateien ansehen ===${NC}"
    echo ""
    echo -e "${CYAN}a)${NC} System Logs (journalctl)"
    echo -e "${CYAN}b)${NC} Samba Logs"
    echo -e "${CYAN}c)${NC} Nginx Logs"
    echo -e "${CYAN}d)${NC} SMART Logs"
    echo -e "${CYAN}e)${NC} Alle Logs durchsuchen"
    echo -e "${CYAN}f)${NC} Zurück zum Hauptmenü"
    echo ""
    read -p "Wähle eine Option (a-f): " choice
    echo ""
    
    case $choice in
        a) view_system_logs ;;
        b) view_samba_logs ;;
        c) view_nginx_logs ;;
        d) view_smart_logs ;;
        e) search_all_logs ;;
        f) show_main_menu ;;
        *) print_error "Ungültige Option!"; sleep 2; show_log_menu ;;
    esac
}

view_system_logs() {
    read -p "Anzahl der letzten Einträge (Standard 20): " LINES
    LINES=${LINES:-20}
    journalctl -n $LINES --no-pager
    read -p "Drücke Enter zum Fortfahren..."
    show_log_menu
}

view_samba_logs() {
    if [ -d "/var/log/samba" ]; then
        echo "Verfügbare Samba Logs:"
        ls -la /var/log/samba/
        echo ""
        read -p "Log-Datei zum Anzeigen (z.B. log.smbd): " LOG_FILE
        if [ -f "/var/log/samba/$LOG_FILE" ]; then
            tail -n 50 "/var/log/samba/$LOG_FILE"
        else
            print_error "Log-Datei nicht gefunden!"
        fi
    else
        print_error "Samba Log-Verzeichnis nicht gefunden!"
    fi
    read -p "Drücke Enter zum Fortfahren..."
    show_log_menu
}

view_nginx_logs() {
    if [ -f "/var/log/nginx/access.log" ]; then
        echo "Letzte 20 Zugriffe:"
        tail -n 20 /var/log/nginx/access.log
        echo ""
        echo "Letzte 10 Fehler:"
        tail -n 10 /var/log/nginx/error.log
    else
        print_error "Nginx Logs nicht gefunden!"
    fi
    read -p "Drücke Enter zum Fortfahren..."
    show_log_menu
}

view_smart_logs() {
    print_info "SMART Status aller Festplatten:"
    for disk in $(lsblk -rno NAME,TYPE | awk '$2=="disk" {print $1}'); do
        echo "=== /dev/$disk ==="
        smartctl -H /dev/$disk 2>/dev/null | grep -i "health\|model\|serial"
    done
    read -p "Drücke Enter zum Fortfahren..."
    show_log_menu
}

search_all_logs() {
    read -p "Suchbegriff eingeben: " SEARCH_TERM
    if [ -n "$SEARCH_TERM" ]; then
        print_info "Suche nach '$SEARCH_TERM' in Logs..."
        grep -r -i "$SEARCH_TERM" /var/log/ --include="*.log" --color=always 2>/dev/null | head -20 || echo "Keine Treffer gefunden."
    else
        print_error "Kein Suchbegriff eingegeben!"
    fi
    read -p "Drücke Enter zum Fortfahren..."
    show_log_menu
}

show_backup_menu() {
    clear
    echo -e "${PURPLE}=== Backup Einstellungen ===${NC}"
    echo ""
    echo -e "${CYAN}a)${NC} Backup jetzt starten"
    echo -e "${CYAN}b)${NC} Cron Job für automatische Backups erstellen"
    echo -e "${CYAN}c)${NC} Bestehende Backup-Jobs anzeigen"
    echo -e "${CYAN}d)${NC} Backup-Konfiguration bearbeiten"
    echo -e "${CYAN}e)${NC} Zurück zum Hauptmenü"
    echo ""
    read -p "Wähle eine Option (a-e): " choice
    echo ""
    
    case $choice in
        a) run_backup_now ;;
        b) setup_backup_cron ;;
        c) show_backup_cron ;;
        d) edit_backup_config ;;
        e) show_main_menu ;;
        *) print_error "Ungültige Option!"; sleep 2; show_backup_menu ;;
    esac
}

run_backup_now() {
    print_perry "Starte Backup jetzt..."
    
    # Erstelle Backup-Verzeichnis
    mkdir -p "$BACKUP_DEST"
    
    # Führe Backup durch
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DEST/backup_$TIMESTAMP.tar.gz"
    
    print_info "Sichere $BACKUP_DIRS nach $BACKUP_FILE..."
    tar -czf "$BACKUP_FILE" -C / $BACKUP_DIRS 2>/dev/null || tar -czf "$BACKUP_FILE" $BACKUP_DIRS
    
    print_success "Backup erfolgreich erstellt: $BACKUP_FILE"
    print_info "Größe: $(du -h "$BACKUP_FILE" | cut -f1)"
    
    # Alte Backups bereinigen
    print_info "Bereinige alte Backups (älter als $LOG_RETENTION_DAYS Tage)..."
    find "$BACKUP_DEST" -name "backup_*.tar.gz" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    
    sleep 3
    show_backup_menu
}

setup_backup_cron() {
    print_info "Aktuelle Backup-Konfiguration:"
    echo "Quellverzeichnisse: $BACKUP_DIRS"
    echo "Zielverzeichnis: $BACKUP_DEST"
    echo ""
    
    echo "Wählen Sie das Backup-Intervall:"
    echo -e "${CYAN}1)${NC} Täglich um 02:00 Uhr"
    echo -e "${CYAN}2)${NC} Wöchentlich (Sonntag) um 03:00 Uhr"
    echo -e "${CYAN}3)${NC} Täglich um 04:30 Uhr"
    echo -e "${CYAN}4)${NC} Benutzerdefiniert"
    echo -e "${CYAN}5)${NC} Zurück zum Backup-Menü"
    echo ""
    read -p "Wähle eine Option (1-5): " cron_choice
    
    case $cron_choice in
        1) CRON_TIME="0 2 * * *" ;;
        2) CRON_TIME="0 3 * * 0" ;;
        3) CRON_TIME="30 4 * * *" ;;
        4) 
            read -p "Cron-Zeitplan eingeben (z.B. '0 2 * * *'): " CRON_TIME
            ;;
        5) show_backup_menu; return ;;
        *) print_error "Ungültige Option!"; sleep 2; setup_backup_cron; return ;;
    esac
    
    # Backup-Skript erstellen
    BACKUP_SCRIPT="/usr/local/bin/perry-nas-backup.sh"
    cat > "$BACKUP_SCRIPT" << 'EOF'
#!/bin/bash
# Perry-NAS Automatisches Backup-Skript

BACKUP_DIRS=$(grep "^BACKUP_DIRS=" /etc/perry-nas-manager.conf | cut -d'=' -f2-)
BACKUP_DEST=$(grep "^BACKUP_DEST=" /etc/perry-nas-manager.conf | cut -d'=' -f2-)
LOG_RETENTION_DAYS=$(grep "^LOG_RETENTION_DAYS=" /etc/perry-nas-manager.conf | cut -d'=' -f2-)

mkdir -p "$BACKUP_DEST"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DEST/backup_$TIMESTAMP.tar.gz"

if tar -czf "$BACKUP_FILE" $BACKUP_DIRS; then
    logger "Perry-NAS: Backup erfolgreich erstellt: $BACKUP_FILE"
    # Alte Backups bereinigen
    find "$BACKUP_DEST" -name "backup_*.tar.gz" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
else
    logger "Perry-NAS: Backup fehlgeschlagen!"
    exit 1
fi
EOF
    
    chmod +x "$BACKUP_SCRIPT"
    
    # Cron Job hinzufügen
    (crontab -l 2>/dev/null | grep -v "perry-nas-backup.sh"; echo "$CRON_TIME $BACKUP_SCRIPT") | crontab -
    
    print_success "Automatisches Backup eingerichtet!"
    print_info "Geplantes Intervall: $CRON_TIME"
    print_info "Skript: $BACKUP_SCRIPT"
    
    sleep 3
    show_backup_menu
}

show_backup_cron() {
    print_info "Aktuelle Backup-Cron-Jobs:"
    crontab -l 2>/dev/null | grep "perry-nas-backup.sh" || echo "Keine Backup-Cron-Jobs gefunden."
    echo ""
    read -p "Drücke Enter zum Fortfahren..."
    show_backup_menu
}

edit_backup_config() {
    print_info "Aktuelle Backup-Konfiguration:"
    echo "BACKUP_DIRS=$BACKUP_DIRS"
    echo "BACKUP_DEST=$BACKUP_DEST"
    echo "LOG_RETENTION_DAYS=$LOG_RETENTION_DAYS"
    echo ""
    
    read -p "Quellverzeichnisse (aktuell: $BACKUP_DIRS): " NEW_BACKUP_DIRS
    read -p "Zielverzeichnis (aktuell: $BACKUP_DEST): " NEW_BACKUP_DEST
    read -p "Aufbewahrungsdauer in Tagen (aktuell: $LOG_RETENTION_DAYS): " NEW_RETENTION_DAYS
    
    NEW_BACKUP_DIRS=${NEW_BACKUP_DIRS:-$BACKUP_DIRS}
    NEW_BACKUP_DEST=${NEW_BACKUP_DEST:-$BACKUP_DEST}
    NEW_RETENTION_DAYS=${NEW_RETENTION_DAYS:-$LOG_RETENTION_DAYS}
    
    # Aktualisiere Konfiguration
    sed -i "s/^BACKUP_DIRS=.*/BACKUP_DIRS=$NEW_BACKUP_DIRS/" "$CONFIG_FILE"
    sed -i "s/^BACKUP_DEST=.*/BACKUP_DEST=$NEW_BACKUP_DEST/" "$CONFIG_FILE"
    sed -i "s/^LOG_RETENTION_DAYS=.*/LOG_RETENTION_DAYS=$NEW_RETENTION_DAYS/" "$CONFIG_FILE"
    
    print_success "Backup-Konfiguration aktualisiert!"
    sleep 2
    show_backup_menu
}

show_system_status() {
    clear
    echo -e "${PURPLE}=== System Status ===${NC}"
    echo ""
    
    # Systeminformationen
    print_info "Systeminformationen:"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo ""
    
    # Festplattennutzung
    print_info "Festplattennutzung:"
    df -h | grep -E "(Filesystem|/dev/)"
    echo ""
    
    # Speicherauslastung
    print_info "Speicherauslastung:"
    free -h
    echo ""
    
    # CPU-Auslastung
    print_info "CPU-Auslastung:"
    uptime
    echo ""
    
    # Dienste Status
    print_info "Wichtige Dienste:"
    services=("smbd" "nginx" "php*-fpm" "smartd")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  $service: ${GREEN}AKTIV${NC}"
        else
            echo -e "  $service: ${RED}INAKTIV${NC}"
        fi
    done
    echo ""
    
    # Temperatur
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_C=$((TEMP / 1000))
        print_info "CPU Temperatur: ${TEMP_C}°C"
    fi
    
    read -p "Drücke Enter zum Fortfahren..."
    show_main_menu
}

show_system_control_menu() {
    clear
    echo -e "${PURPLE}=== System Steuerung ===${NC}"
    echo ""
    echo -e "${RED}ACHTUNG: Diese Aktionen beeinflussen das System!${NC}"
    echo ""
    echo -e "${CYAN}a)${NC} System neu starten"
    echo -e "${CYAN}b)${NC} System herunterfahren"
    echo -e "${CYAN}c)${NC} Nur einen Dienst neu starten"
    echo -e "${CYAN}d)${NC} Zurück zum Hauptmenü"
    echo ""
    read -p "Wähle eine Option (a-d): " choice
    echo ""
    
    case $choice in
        a) confirm_and_reboot ;;
        b) confirm_and_shutdown ;;
        c) restart_service ;;
        d) show_main_menu ;;
        *) print_error "Ungültige Option!"; sleep 2; show_system_control_menu ;;
    esac
}

confirm_and_reboot() {
    print_warning "System NEU STARTEN? Alle ungespeicherten Daten gehen verloren!"
    read -p "Sind Sie sicher? (ja/NEIN): " CONFIRM
    if [ "$CONFIRM" = "ja" ]; then
        print_perry "Starte System neu..."
        shutdown -r now
    else
        print_info "Neustart abgebrochen."
        sleep 2
        show_system_control_menu
    fi
}

confirm_and_shutdown() {
    print_warning "System HERUNTERFAHREN? Alle ungespeicherten Daten gehen verloren!"
    read -p "Sind Sie sicher? (ja/NEIN): " CONFIRM
    if [ "$CONFIRM" = "ja" ]; then
        print_perry "Fahre System herunter..."
        shutdown -h now
    else
        print_info "Herunterfahren abgebrochen."
        sleep 2
        show_system_control_menu
    fi
}

restart_service() {
    print_info "Verfügbare Dienste:"
    systemctl list-units --type=service --state=active | grep -E "(smbd|nginx|php|smartd|cron)" | awk '{print $1}'
    echo ""
    read -p "Name des Dienstes zum Neustart: " SERVICE_NAME
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_perry "Starte Dienst $SERVICE_NAME neu..."
        systemctl restart "$SERVICE_NAME"
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            print_success "Dienst $SERVICE_NAME erfolgreich neu gestartet."
        else
            print_error "Fehler beim Neustart des Dienstes $SERVICE_NAME!"
        fi
    else
        print_error "Dienst $SERVICE_NAME ist nicht aktiv!"
    fi
    sleep 3
    show_system_control_menu
}

edit_config() {
    print_info "Aktuelle Konfiguration:"
    cat "$CONFIG_FILE"
    echo ""
    
    read -p "Drücke Enter zum Bearbeiten der Konfigurationsdatei in nano..."
    nano "$CONFIG_FILE"
    
    # Lade neue Konfiguration
    source "$CONFIG_FILE"
    
    print_success "Konfiguration aktualisiert!"
    sleep 2
    show_main_menu
}

# Starte Hauptmenü
show_main_menu
