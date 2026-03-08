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

Angenommen, das Update-Skript befindet sich im Unterordner updates:


# In das geklonte Hauptverzeichnis wechseln (falls noch nicht geschehen)
```bash
cd perry-nas 
```

# In das Verzeichnis des Web-Updates wechseln
```bash
cd update/
```

2. Update-Skript vorbereiten und ausführen

Das Skript perry-web-update.sh installiert das neue Dashboard, indem es die Dateien /var/www/html/index.php und /var/www/html/data.php überschreibt.

Als Tests habe verschiedene Themen erstellt.: perry-theme-pip-boy.sh  perry-theme-startrek.sh  perry-web-update2.sh  perry-web-update.sh


# Skript ausführbar machen
```bash
chmod +x perry-theme-pip-boy.sh
```
# Skript mit Root-Rechten ausführen
```bash
sudo ./perry-theme-pip-boy.sh
```

3. Abschluss und Test

Nach erfolgreicher Ausführung des Skripts:

Der Webserver Nginx und der PHP-Dienst werden neu gestartet.

Besuchen Sie die IP-Adresse Ihres NAS im Webbrowser: http://[IP-ADRESSE-PI]/

Sie sollten nun das neue, lila Dashboard mit den Systemgrafiken sehen.

📋 Manuelle Installation (Alternativ)
Falls Sie das Repository nicht klonen möchten, können Sie das Skript auch manuell von GitHub herunterladen:

1. Skript herunterladen
Verwenden Sie wget (oder curl), um die Datei direkt herunterzuladen:


# URL entsprechend Ihrem Repository-Pfad anpassen

```bash
wget https://raw.githubusercontent.com/RamonWeb/perry-nas/main/updates/perry-theme-pip-boy.sh
```

# Berechtigungen setzen

```bash
chmod +x perry-theme-pip-boy.sh
```

2. Skript ausführen

```bash
sudo ./perry-theme-pip-boy.sh
```

🐛 Problembehebung
Wenn das neue Dashboard nicht angezeigt wird, prüfen Sie bitte folgende Punkte:

Berechtigungen: Stellen Sie sicher, dass das Skript mit sudo ausgeführt wurde.

PHP-FPM: Überprüfen Sie, ob der PHP-Dienst korrekt läuft (ersetzen Sie 8.4 durch Ihre installierte Version):

```bash
sudo systemctl status php8.4-fpm
```
Nginx Logs: Prüfen Sie die Webserver-Fehlerprotokolle:

```bash
sudo tail -f /var/log/nginx/error.log
```

Wenn Sie einen der erweiterten Schritte wie den Health Check oder die Performance-Optimierung benötigen, teilen Sie mir dies bitte mit!
