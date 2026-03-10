📟 Perry-NAS: Pip-Boy Terminal & System Management
Ein stylisches, Fallout-inspiriertes Management-System für den Raspberry Pi 5 unter Debian 13. Dieses Projekt verwandelt dein NAS in ein sich selbst wartendes Terminal mit Echtzeit-Überwachung und automatisierter Datensicherheit.

🌟 Features
Pip-Boy Dashboard: Ein monochrom-grünes Web-Interface zur Überwachung von CPU-Last, Temperatur, RAM und Speicherplatz.

Dual-Disk Monitoring: Volle Unterstützung für zwei Festplatten inklusive SMART-Health-Status ("PASSED" oder "FAILED").

Automatisierte Sicherheit:

Backups: Nächtliche Spiegelung von Disk 1 auf Disk 2 via rsync.

Updates: Wöchentliche System-Updates (apt-get upgrade) ohne Benutzereingriff.

Reports: Wöchentlicher Statusbericht per E-Mail inklusive einer Liste aller aktualisierten Pakete.

Hardware-Wartung: Regelmäßige SMART-Selbsttests der Festplatten im Hintergrund.

🛠 Installation
Repository klonen:

Bash

git clone https://github.com/DEIN_USERNAME/perry-nas.git
cd perry-nas
Installer ausführen:
Das mitgelieferte Master-Skript installiert alle Abhängigkeiten (Nginx, PHP, Smartmontools, msmtp) und konfiguriert das System automatisch.

Bash

sudo bash install_perry_nas.sh
E-Mail-Versand einrichten:
Damit die Reports verschickt werden können, musst du deine E-Mail-Daten in /etc/msmtprc hinterlegen.

📊 Dashboard Ansicht
Das Dashboard ist nach der Installation über die IP-Adresse deines Raspberry Pi erreichbar (z.B. http://192.168.178.50).

CPU: Auslastung & aktuelle Temperatur des Pi 5.

Storage: Belegter Speicherplatz beider Platten.

Health: Live-Abfrage der SMART-Werte. Wenn eine Platte stirbt, wird die Anzeige ROT.

Backup: Datum und Uhrzeit des letzten erfolgreichen Backups.

📂 Dateistruktur
/var/www/html/ - Die Weboberfläche (PHP/JS).

/usr/local/bin/ - Die Management-Skripte für Backup, Update und Reporting.

/etc/cron.d/perry_nas - Die Zeitpläne für alle automatisierten Aufgaben.

⚠️ Voraussetzungen
Hardware: Raspberry Pi 5 (oder 4).

OS: Debian 13 / Raspberry Pi OS (Bookworm/Trixie).

Speicher: Zwei gemountete Festplatten unter /mnt/perry-nas und /mnt/perry-nas-2.

🤝 Mitwirken
Hast du Ideen für neue Pip-Boy-Widgets? Erstelle gerne einen Pull-Request oder öffne ein Issue!