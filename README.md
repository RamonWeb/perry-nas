# # Perry-NAS 🍐

![Perry-NAS](https://img.shields.io/badge/Perry--NAS-Raspberry%20Pi%205-C51A4A?style=for-the-badge&logo=raspberrypi)
![HomeRacker](https://img.shields.io/badge/Gehäuse-HomeRacker-00A2E8?style=for-the-badge)
![PCIe SATA](https://img.shields.io/badge/Storage-PCIe_SATA_Adapter-FF6B6B?style=for-the-badge)
![Debian Trixie](https://img.shields.io/badge/Debian-Trixie-A81D33?style=for-the-badge&logo=debian)

**Perry-NAS** - Dein persönlicher, professioneller NAS-Server auf Basis des Raspberry Pi 5 mit PCIe SATA Adapter, verpackt im modularen HomeRacker Gehäuse von KellerLab.

## ✨ Perry-NAS Features

- **🍐 Einfache Installation** - Perry-NAS Setup in wenigen Minuten
- **🔄 PCIe SATA Adapter** - 2-Channel SATA für bis zu 2 Festplatten
- **🏠 HomeRacker Gehäuse** - Modulares System von KellerLab
- **⚡ Raspberry Pi 5** - Mit 4GB RAM für optimale Performance
- **📁 Samba Freigaben** - Windows 11 kompatibel
- **🌐 Web-Status Interface** - Echtzeit-Monitoring mit Perry-Theming
- **🔌 Integrierte Stromversorgung** - 5V & 12V PSU Module
- **❤️ S.M.A.R.T. Monitoring** - Festplatten-Gesundheitsüberwachung
- **🔒 Sicherheit** - Firewall und Benutzer-Authentifizierung

## 🛠️ Perry-NAS Hardware Komponenten

| Komponente | Spezifikation |
|------------|---------------|
| **Name** | **Perry-NAS** |
| **Raspberry Pi** | Pi 5 4GB |
| **SATA Adapter** | PCIe to 2-Ch SATA Adapter für Raspberry Pi 5 |
| **Gehäuse** | HomeRacker System von KellerLab |
| **PSU Module** | 5V & 12V Stromversorgung |
| **Storage Module** | Festplatten-Einschub für HDD/SSD |
| **Switch Module** | LAN Switch Einschub |
| **Festplatte** | HDD über SATA Adapter |

## 🏗️ Perry-NAS HomeRacker Aufbau

```
[Perry-NAS HomeRacker Stack]
├── PSU Einschub (5V/12V)
├── Raspberry Pi 5 Module
├── PCIe SATA Adapter Module  
├── Festplatten Module (HDD)
└── LAN Switch Module
```

## 🚀 Perry-NAS Schnellstart

### 1. Hardware zusammenbauen

1. **HomeRacker Module** für Perry-NAS stapeln
2. **PCIe SATA Adapter** an Raspberry Pi 5 anschließen
3. **Festplatte** an SATA Adapter anschließen
4. **Stromversorgung** an PSU Module anschließen
5. **Netzwerk** an Switch Module anschließen

### 2. System vorbereiten

```bash
# Raspberry Pi OS Trixie installieren
# PCIe Support ist in Trixie bereits enthalten

# SSH aktivieren
sudo raspi-config
# → Interface Options → SSH → Enable
```

### 3. Perry-NAS Setup

```bash
# Repository klonen
sudo apt install git
git clone https://github.com/RamonWeb/perry-nas.git
cd perry-nas

# Perry-NAS Setup ausführen
chmod +x perry-nas-setup.sh
sudo ./perry-nas-setup.sh
```

**Während der Installation:**
- Perry-NAS Benutzername eingeben (z.B. `perry`)
- Samba Passwort setzen
- PCIe Festplatten-Device bestätigen (z.B. `sda`)

### 4. Zugriff testen

**Web-Interface:**
```
http://[IP-ADRESSE-PI]/
```

**Samba Freigabe:**
```
\\[IP-ADRESSE-PI]\Perry-NAS
```

## 📋 Detaillierte Installation

### Schritt 1: System-Update

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt autoremove -y
```

### Schritt 2: Script herunterladen

```bash
wget https://raw.githubusercontent.com/RamonWeb/perry-nas/main/perry-nas-setup.sh
chmod +x perry-nas-setup.sh
```

### Schritt 3: Installation

```bash
sudo ./perry-nas-setup.sh
```

Das Perry-NAS Script führt automatisch aus:
- Systemaktualisierung
- Paketinstallation (Samba, Nginx, PHP, S.M.A.R.T. Tools)
- PCIe SATA Performance-Optimierung
- Festplattenpartitionierung
- Samba Konfiguration
- Web-Interface Setup
- Firewall Konfiguration
- Autostart Einrichtung

## 🍐 Perry-NAS Web Interface

Das Perry-NAS Web-Interface bietet:

- **🍐 Perry-Theming** - Einzigartiges lila Design
- **Systemübersicht** - Hostname, Benutzer, OS, Uptime
- **Festplattennutzung** - Echtzeit-Überwachung
- **Systemressourcen** - CPU, RAM, Temperatur
- **Dienstestatus** - Samba, Webserver, PHP-FPM, S.M.A.R.T.
- **Zugriffsinformationen** - Alle Verbindungsdaten auf einen Blick

## 🔧 Perry-NAS Verwaltung

### Dienste neu starten

```bash
# Samba
sudo systemctl restart smbd

# Webserver
sudo systemctl restart nginx

# PHP
sudo systemctl restart php8.3-fpm

# S.M.A.R.T. Monitoring
sudo systemctl restart smartd
```

### Perry-NAS Status prüfen

```bash
# Health Check durchführen
sudo ./perry-health-check.sh

# Alle Dienste prüfen
sudo systemctl status smbd nginx php8.3-fpm smartd

# Festplattenstatus
df -h /mnt/perry-nas

# S.M.A.R.T. Status
sudo smartctl -a /dev/sda
```

### Perry-NAS Reset

```bash
# Für neue Tests
chmod +x perry-nas-reset.sh
sudo ./perry-nas-reset.sh
```

## 🌐 Zugriff von verschiedenen Systemen

### Windows 11
```
\\192.168.1.100\Perry-NAS
```
*Tipp: Bei Verbindungsproblemen SMB1 in Windows Features aktivieren*

### Linux
```bash
sudo mount -t cifs //192.168.1.100/Perry-NAS /mnt/perry-nas -o username=perry
```

### macOS
```
smb://192.168.1.100/Perry-NAS
```

### Android
- ES File Explorer oder Solid Explorer
- SMB-Verbindung zur Perry-NAS IP

## 🗂️ Perry-NAS Projektstruktur

```
perry-nas/
├── perry-nas-setup.sh              # Haupt-Setup Script
├── perry-health-check.sh           # Health Monitoring
├── perry-nas-stats.sh              # Performance Stats
├── perry-nas-reset.sh              # Reset Script
├── docs/
│   ├── homeracker-setup.md         # HomeRacker Aufbau
│   ├── pcie-adapter-guide.md       # PCIe Adapter Anleitung
│   └── troubleshooting.md          # Problembehebung
├── web/
│   └── perry-theme/                # Perry-NAS Web Theme
├── README.md                       # Diese Datei
└── LICENSE
```

## ⚙️ Perry-NAS Konfiguration

### Samba Konfiguration
- **Freigabe:** `/mnt/perry-nas`
- **Name:** `Perry-NAS`
- **Protokoll:** SMB2/SMB3
- **Sicherheit:** User Authentication
- **Workgroup:** WORKGROUP

### Web-Server
- **Port:** 80
- **Root:** `/var/www/html`
- **PHP:** 8.3+
- **Theme:** Perry-NAS lila Design

### PCIe SATA Optimierungen
- **Power Management:** Max Performance
- **Read-Ahead:** 1024KB
- **Filesystem:** ext4 mit writeback

## 🔒 Perry-NAS Sicherheit

- Firewall aktiviert (SSH, HTTP, Samba)
- SSH Zugang gesichert
- Samba mit Benutzer-Authentifizierung
- S.M.A.R.T. Health Monitoring
- Regelmäßige Sicherheitsupdates

## ⚡ Perry-NAS Performance Optimierung

### Für PCIe SATA

```bash
# In /etc/fstab für bessere Performance:
/dev/sda1  /mnt/perry-nas  ext4  defaults,noatime,data=writeback,nobarrier,nofail  0  2

# SATA Power Management deaktivieren
echo max_performance | sudo tee /sys/class/scsi_host/host*/link_power_management_policy
```

### Samba für PCIe optimieren

```bash
# In /etc/samba/smb.conf unter [global]:
socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
use sendfile = yes
strict locking = no
read raw = yes
write raw = yes
```

## 🐛 Perry-NAS Problembehebung

### PCIe SATA Adapter wird nicht erkannt

```bash
# PCIe Bus scannen
lspci -v

# Kernel Module laden
sudo modprobe ahci

# Neustart des PCIe Busses
echo 1 | sudo tee /sys/bus/pci/rescan
```

### Festplatte nicht sichtbar

```bash
# SCSI Bus rescan
echo "- - -" | sudo tee /sys/class/scsi_host/host*/scan

# Manuell partitionieren
sudo parted /dev/sda mklabel gpt
sudo parted /dev/sda mkpart primary ext4 0% 100%
```

### Web-Interface nicht erreichbar

```bash
sudo systemctl status nginx
sudo tail -f /var/log/nginx/error.log
```

### Samba nicht sichtbar in Windows

```bash
# Auf Windows: Direkt mit IP verbinden
\\192.168.1.100

# Perry-NAS Samba Status prüfen
sudo systemctl status smbd
sudo smbclient -L //localhost -U perry
```

## 📈 Perry-NAS Erweiterungsmöglichkeiten

### Zweite Festplatte hinzufügen

Dein PCIe Adapter unterstützt 2 SATA Ports:

```bash
# Zweite Festplatte partitionieren
sudo parted /dev/sdb mklabel gpt
sudo parted /dev/sdb mkpart primary ext4 0% 100%

# RAID 1 für Redundanz
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1
```

### HomeRacker Erweiterungen

- **Kühlungs-Module** - Für aktive Kühlung
- **Display-Module** - Für Status-Anzeige
- **USB-Hub Module** - Für weitere Peripherie

### Zusätzliche Dienste

- **Docker** - Container-Unterstützung
- **Plex Media Server** - Media Streaming
- **Nextcloud** - Cloud-Speicher
- **Pi-hole** - Netzwerk-Werbeblocker

## Dokumentation der Module

Hier findest du die Details zu den einzelnen Tools:

* 📂 **Admin:** [Anleitung öffnen](Admin/README.md)
* 📂 **Master:** [Anleitung öffnen](master/README.md)
* 📂 **Update:** [Anleitung öffnen](update/README.md)

## 🤝 Beitragen

Da Perry-NAS ein spezielles Hardware-Setup verwendet, sind Erfahrungsberichte besonders wertvoll!

Beiträge sind willkommen für:
- PCIe SATA Performance Optimierungen
- HomeRacker Modul-Konfigurationen
- Strommanagement-Lösungen
- Web-Interface Erweiterungen

**Beitragsprozess:**
1. Fork das Repository
2. Erstelle einen Feature Branch
3. Committe deine Änderungen
4. Push zum Branch
5. Erstelle einen Pull Request

## 📄 Lizenz

Dieses Projekt ist unter der MIT Lizenz veröffentlicht - siehe [LICENSE](LICENSE) Datei für Details.

## 🙏 Danksagung

- **KellerLab** für das HomeRacker System
- **Raspberry Pi Foundation** für den Pi 5
- **PCIe SATA Adapter Hersteller** für den Hardware-Support
- **Samba Team** für die Dateifreigabe-Lösung
- **Debian Projekt** für das stabile Betriebssystem

## 📞 Support

Bei Problemen mit Perry-NAS:

1. **Issues** auf GitHub öffnen
2. **Hardware-Checks** durchführen
3. **Logs** bereitstellen: `sudo journalctl -u smbd -f`

---

**⭐ Wenn dir Perry-NAS gefällt, vergiss nicht das Repository zu starred!**

**🍐 Perry-NAS - Dein zuverlässiger Speicherpartner!**

---

*Letzte Aktualisierung: November 2025 | Compatible with Raspberry Pi 5 | HomeRacker Gehäuse | PCIe SATA Adapter*perry-nas
 
