# 📟 PERRY-NAS: Ultimate Pip-Boy Management Suite

Dieses Projekt verwandelt einen **Raspberry Pi 5** unter **Debian 13 (Trixie)** in ein hochautomatisiertes NAS-System. Es kombiniert ein Fallout-inspiriertes Web-Interface mit professionellen Monitoring- und Backup-Tools.

---

## 📑 Inhaltsverzeichnis
1. [Features](#-features)
2. [Hardware-Setup](#-hardware-setup)
3. [Installation](#-installation)
4. [E-Mail Konfiguration (Gmail/msmtp)](#-e-mail-konfiguration)
5. [Automatisierung (Cronjobs)](#-automatisierung)
6. [SMART Monitoring](#-smart-monitoring)

---

## 🌟 Features

* **Pip-Boy Dashboard:** Echtzeit-Visualisierung von CPU (Last/Temp), RAM und Disk-Usage.
* **Smart-Health-Check:** Sofortige Statusanzeige (OK/BAD) basierend auf SMART-Werten.
* **Inkrementelles Backup:** Nächtliche Spiegelung von Disk 1 auf Disk 2 via `rsync`.
* **Stable CLI Updates:** Wöchentliche System-Updates mit dem stabilen `apt-get` Interface.
* **Kombinierter Wochenbericht:** E-Mail-Report jeden Montag mit Hardware-Status und Update-Liste.

---

## 🔌 Hardware-Setup

* **Host:** Raspberry Pi 5
* **OS:** Debian 13 (Trixie)
* **Mount-Points:**
    * `/mnt/perry-nas` (Erste Festplatte / sda)
    * `/mnt/perry-nas-2` (Zweite Festplatte / sdb)

---

## 🛠 Installation

### 1. Repository klonen
```bash
git clone https://github.com/RamonWeb/perry-nas.git
cd perry-nas
```
### 2. Master-Installer ausführen
Das Skript installiert Nginx, PHP, Smartmontools, rsync und msmtp.Bash sudo bash install_perry_nas.sh

## 📧 E-Mail Konfiguration
Um Berichte zu empfangen, wird msmtp genutzt.
1. Gmail vorbereitenAktiviere 2-Faktor-Authentisierung in deinem Google-Konto.Erstelle ein App-Passwort (Sicherheit -> App-Passwörter). 

Notiere den 16-stelligen Code.

2. msmtp konfigurieren
Erstelle oder bearbeite die Datei 

/etc/msmtprc:
```bash
sudo nano /etc/msmtprc
```
inhalt
```bash
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           DEINE_EMAIL@gmail.com
user           DEINE_EMAIL@gmail.com
password       DEIN_16_STELLIGES_APP_PASSWORT
```
## 3. Berechtigungen setzen
```bash
sudo chmod 600 /etc/msmtprc
sudo chown www-data:www-data /etc/msmtprc
```
⏰ AutomatisierungDie Zeitpläne sind in ```bash/etc/cron.d/perry_nas ```definiert:

> Uhrzeit--Tag----Skript-------------Funktion >
02:00,Täglich,nas_backup.sh,Spiegelung Disk 1 -> Disk 2
> 
04:00,Montag,nas_update.sh,System-Updates (apt-get)

08:00,Montag,nas_report.sh,Versand des Wochenberichts


## 🔍 SMART Monitoring
Das System überwacht kritische Festplatten-Fehler. Ein "vertretbarer" Fehlerwert ist bei den folgenden IDs immer 0:
## ID 5 (Reallocated Sectors): Defekte Sektoren, die ersetzt wurden.
## ID 197 (Current Pending Sectors): Instabile Sektoren.
## ID 198 (Offline Uncorrectable): Schwere Oberflächenschäden.
Sobald ein Wert > 0 erkannt wird, markiert das Dashboard die entsprechende Platte als BAD.

## 📂 Projekt-Struktur im Repo
- ```install_perry_nas.sh```: Der Master-Installer.
- ```index.php```: Pip-Boy Web-Frontend.
- ```data.php```: Backend API (liefert JSON-Daten).
- ```nas_backup.sh```: Backup-Logik.
- ```nas_update.sh```: Update-Logik (CLI Stable).
- ```nas_report.sh```: E-Mail-Generator.
