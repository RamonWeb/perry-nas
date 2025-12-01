✨ Perry-NAS Web-Dashboard Update (v3.0)
Dieses Dokument beschreibt die Installation des Updates für das Perry-NAS Web-Interface, welches die Systemstatus-Anzeige um ein grafisches Dashboard (Chart.js) im lila Perry-Theming erweitert.

🖼️ Update-Features
Grafische Darstellung: Umwandlung der textuellen Statusausgabe in interaktive Donut- und Balkendiagramme (Festplatte, RAM, Load Average).

Design: Implementiert das gewünschte lila Perry-Theming mit verbesserter Übersichtlichkeit.

Technologie: Nutzt PHP (mind. 8.3+) für die Datenerfassung und JavaScript (Chart.js) für die Visualisierung.

Stabilität: Das Update umfasst das Skript perry-web-update.sh, das Berechtigungen und den Neustart der Dienste Nginx und PHP-FPM automatisch verwaltet.

🚀 Installations-Anleitung (GitHub-basiert)
Diese Anleitung setzt voraus, dass Sie das Haupt-Setup (perry-nas-setup.sh) bereits ausgeführt haben und das Perry-NAS Repository lokal geklont ist.

1. Zum Update-Ordner navigieren
Angenommen, das Update-Skript befindet sich im Unterordner updates/web-v3:

Bash

# In das geklonte Hauptverzeichnis wechseln (falls noch nicht geschehen)
cd perry-nas 

# In das Verzeichnis des Web-Updates wechseln
cd updates/web-v3
2. Update-Skript vorbereiten und ausführen
Das Skript perry-web-update.sh installiert das neue Dashboard, indem es die Dateien /var/www/html/index.php und /var/www/html/data.php überschreibt.

Bash

# Skript ausführbar machen
chmod +x perry-web-update.sh

# Skript mit Root-Rechten ausführen
sudo ./perry-web-update.sh
3. Abschluss und Test
Nach erfolgreicher Ausführung des Skripts:

Der Webserver Nginx und der PHP-Dienst werden neu gestartet.

Besuchen Sie die IP-Adresse Ihres NAS im Webbrowser: http://[IP-ADRESSE-PI]/

Sie sollten nun das neue, lila Dashboard mit den Systemgrafiken sehen.

📋 Manuelle Installation (Alternativ)
Falls Sie das Repository nicht klonen möchten, können Sie das Skript auch manuell von GitHub herunterladen:

1. Skript herunterladen
Verwenden Sie wget (oder curl), um die Datei direkt herunterzuladen:

Bash

# URL entsprechend Ihrem Repository-Pfad anpassen
wget https://raw.githubusercontent.com/RamonWeb/perry-nas/main/updates/web-v3/perry-web-update.sh

# Berechtigungen setzen
chmod +x perry-web-update.sh
2. Skript ausführen
Bash

sudo ./perry-web-update.sh
🐛 Problembehebung
Wenn das neue Dashboard nicht angezeigt wird, prüfen Sie bitte folgende Punkte:

Berechtigungen: Stellen Sie sicher, dass das Skript mit sudo ausgeführt wurde.

PHP-FPM: Überprüfen Sie, ob der PHP-Dienst korrekt läuft (ersetzen Sie 8.4 durch Ihre installierte Version):

Bash

sudo systemctl status php8.4-fpm
Nginx Logs: Prüfen Sie die Webserver-Fehlerprotokolle:

Bash

sudo tail -f /var/log/nginx/error.log