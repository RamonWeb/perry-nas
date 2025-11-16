
# Perry-NAS Manager

**Vollständiger Server Manager für dein Perry-NAS System**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-Raspberry%20Pi%205-brightgreen)](https://www.raspberrypi.com/)
[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)

## 🍐 Über Perry-NAS Manager

Perry-NAS Manager ist ein umfassendes Management-Tool für dein Perry-NAS System. Es ermöglicht dir die vollständige Kontrolle deines NAS-Servers über eine intuitive Menüführung per SSH als root. Das Tool integriert sich nahtlos in dein bestehendes Perry-NAS Setup und erweitert es um alle benötigten Management-Funktionen.

## 🚀 Features

### 🔧 Festplatten Management
- **Anzeige** verfügbarer Festplatten und Partitionen
- **Einrichtung** neuer Festplatten mit Formatierung und automatischem Mounting
- **Samba-Freigaben** erstellen, verwalten und neu starten
- **Überblick** über aktuelle Mounts und fstab-Einträge

### 🔄 System Updates
- **Anzeige** verfügbarer System-Updates
- **Vollständige** Systemaktualisierung (apt update && upgrade)
- **Sicherheits-Updates** separat installieren

### 📝 Log-Dateien
- **System Logs** (journalctl) anzeigen und filtern
- **Samba Logs** einsehen und analysieren
- **Nginx Logs** für Web- und Zugriffs-Überwachung
- **SMART Status** aller Festplatten überprüfen
- **Volltextsuche** in allen System-Logs

### 💾 Automatische Backups
- **Sofort-Backups** starten
- **Automatische Backups** per Cron-Job einrichten
- **Konfigurierbare** Backup-Quellen und -Ziele
- **Automatische Bereinigung** alter Backup-Dateien
- **Flexible Zeitpläne** (täglich, wöchentlich, benutzerdefiniert)

### 📊 System Status
- **Vollständige Systemübersicht** (Hostname, OS, Kernel)
- **Festplattennutzung** und Speicherplatz-Überblick
- **Speicher- und CPU-Auslastung** in Echtzeit
- **Status** aller wichtigen Dienste (Samba, Nginx, PHP-FPM, SMART)
- **Temperaturüberwachung** des Systems

### ⚡ System Steuerung
- **System neu starten** oder **herunterfahren**
- **Einzelne Dienste** neu starten
- **Sichere** Befehlsausführung mit Bestätigung

## 🛠️ Installation

1. **Herunterladen des Scripts:**
   ```bash
   wget https://raw.githubusercontent.com/RamonWeb/perry-nas-manager/main/perry-nas-manager.sh
   ```

2. **Ausführbar machen:**
   ```bash
   chmod +x perry-nas-manager.sh
   ```

3. **Als root ausführen:**
   ```bash
   sudo ./perry-nas-manager.sh
   ```

## 📋 Voraussetzungen

- **Raspberry Pi 5** (optimiert für Perry-NAS Setup)
- **Linux Distribution** (getestet mit Raspberry Pi OS Trixi)
- **Root-Rechte** (für Festplatten- und System-Management)
- **Installierte Perry-NAS Komponenten** (Samba, Nginx, PHP, SMART-Tools)

## 🎨 Perry-NAS Design

Das Tool verwendet das charakteristische Perry-NAS Farbdesign:
- **Purple** (`#8A2BE2`) - Hauptfarbe
- **Blue** (`#0000FF`) - Informationen
- **Green** (`#008000`) - Erfolge
- **Red** (`#FF0000`) - Warnungen/Fehler
- **Yellow** (`#FFFF00`) - Warnungen

## 📖 Verwendung

Starte das Tool mit:
```bash
sudo ./perry-nas-manager.sh
```

Navigiere durch das Hauptmenü mit den Zahlen 0-7:
- `1` - Festplatten Management
- `2` - System Updates
- `3` - Log Dateien
- `4` - Backup Einstellungen
- `5` - System Status
- `6` - System Steuerung
- `7` - Konfiguration bearbeiten
- `0` - Beenden

## ⚙️ Konfiguration

Das Tool erstellt automatisch eine Konfigurationsdatei unter `/etc/perry-nas-manager.conf` mit folgenden Einstellungen:

```bash
# Perry-NAS Manager Konfiguration
BACKUP_DIRS="/mnt/perry-nas"
BACKUP_DEST="/mnt/perry-nas/backups"
LOG_RETENTION_DAYS=30
DEFAULT_USER="perry"
```

Die Konfiguration kann über das Tool-Menü bearbeitet werden.

## 🛡️ Sicherheit

- **Root-Check** bei jedem Start
- **Bestätigungsabfragen** für kritische Aktionen
- **Automatische Backups** vor wichtigen Änderungen (geplant)
- **Logging** aller wichtigen Aktionen

## 🤝 Mitwirken

Beiträge sind willkommen! Bitte erstelle ein Issue oder sende einen Pull Request.

## 📄 Lizenz

Dieses Projekt steht unter der [GNU General Public License v3.0](LICENSE).

## 🍐 Perry-NAS Ecosystem

Teil der Perry-NAS Toolchain:
- [perry-nas-setup](https://github.com/dein-username/perry-nas-setup) - Setup Script
- [perry-nas-manager](https://github.com/dein-username/perry-nas-manager) - Management Tool
- [perry-nas-web](https://github.com/dein-username/perry-nas-web) - Web Interface (geplant)

---

## 💬 Support

Für Fragen oder Probleme erstelle bitte ein [GitHub Issue](https://github.com/dein-username/perry-nas-manager/issues).

---

**梨 Perry-NAS Manager - Dein zuverlässiger NAS-Partner** 🍐
```
