#!/bin/bash
# Perry-NAS CPU-Update Script
# Fügt CPU-Auslastung in Prozent als horizontales Balkendiagramm hinzu.
set -e

# Farbdefinitionen
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_perry() { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Root Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen: sudo $0"
    exit 1
fi

print_perry "Starte CPU-Dashboard-Update (Balkendiagramm 0-100%)"

# --- 1. Aktualisiertes PHP-Skript zur Datenerfassung (data.php) ---
# Das PHP-Skript bleibt unverändert, da die Datenstruktur korrekt ist.
print_perry "data.php bleibt unverändert (Datenstruktur ist korrekt)."

cat > /var/www/html/data.php << 'EOF'
<?php
header('Content-Type: application/json');

function get_disk_usage() {
    $disk_total = disk_total_space('/mnt/perry-nas');
    $disk_free = disk_free_space('/mnt/perry-nas');
    if ($disk_total === false || $disk_free === false) {
        return ['error' => 'Disk information unavailable'];
    }
    $disk_used = $disk_total - $disk_free;
    $disk_used_percent = round(($disk_used / $disk_total) * 100, 1);

    return [
        'total' => round($disk_total / (1024*1024*1024), 2),
        'used' => round($disk_used / (1024*1024*1024), 2),
        'used_percent' => $disk_used_percent,
    ];
}

function get_ram_usage() {
    $free_output = shell_exec('free -b | grep Mem:');
    if (!$free_output) {
        return ['error' => 'RAM information unavailable'];
    }

    $parts = preg_split('/\s+/', $free_output);
    $total = (float)$parts[1];
    $used = (float)$parts[2];
    $used_percent = round(($used / $total) * 100, 1);

    return [
        'total' => round($total / (1024*1024*1024), 2),
        'used' => round($used / (1024*1024*1024), 2),
        'used_percent' => $used_percent,
    ];
}

function get_load_avg() {
    $load = sys_getloadavg();
    return [
        '1min' => $load[0],
        '5min' => $load[1],
        '15min' => $load[2],
    ];
}

function get_cpu_usage() {
    // Liest die Idle-Zeit aus 'top' und berechnet 100 - Idle
    // $8 ist die Spalte für die Idle-Zeit ('id') in den meisten Linux-Distributionen
    $cpu_idle = shell_exec("top -bn1 | grep 'Cpu(s)' | awk '{print $8}' | sed 's/%,//' | tr ',' '.'");
    $cpu_usage = 100 - floatval(trim($cpu_idle));
    // Wenn die Berechnung fehlschlägt oder negativ ist, geben wir 0 zurück
    return ['usage_percent' => round($cpu_usage, 1) < 0 ? 0 : round($cpu_usage, 1)];
}

$status = [
    'hostname' => trim(shell_exec('hostname')),
    'uptime' => trim(shell_exec('uptime -p')),
    'disk' => get_disk_usage(),
    'ram' => get_ram_usage(),
    'load' => get_load_avg(),
    'cpu' => get_cpu_usage(),
    'timestamp' => date('Y-m-d H:i:s')
];

echo json_encode($status, JSON_PRETTY_PRINT);
?>
EOF

print_success "data.php wurde erfolgreich mit CPU-Funktion aktualisiert."

# --- 2. Aktualisiertes HTML/JS Dashboard (index.php) ---
print_perry "Aktualisiere grafisches Dashboard (/var/www/html/index.php)"

cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Perry-NAS Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        /* Der gewünschte LILA Hintergrund */
        body {
            font-family: 'Arial', sans-serif;
            background-color: #6a1b9a; /* Dunkellila */
            color: #ffffff;
            margin: 0;
            padding: 20px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .container {
            width: 100%;
            max-width: 1200px;
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
        }
        h1 {
            color: #ffd700; /* Gold */
            text-align: center;
            margin-bottom: 30px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .stat-box {
            background-color: rgba(255, 255, 255, 0.9);
            color: #333;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }
        .chart-container {
            background: #fff;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        /* Neue 3-Spalten-Struktur */
        .grid-3 {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        /* Styling für den CPU-Balken, um ihn größer zu machen */
        #cpuChart {
            height: 150px !important; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🍐 Perry-NAS System-Dashboard</h1>
        
        <div class="stats-grid">
            <div class="stat-box" id="hostname-box"></div>
            <div class="stat-box" id="uptime-box"></div>
            <div class="stat-box" id="timestamp-box"></div>
        </div>

        <h2>Auslastung (Prozessor und Speicher)</h2>
        <div class="grid-3">
            <div class="chart-container">
                <h3 id="cpu-label">Prozessor-Auslastung (0.0%)</h3>
                <canvas id="cpuChart"></canvas>
            </div>
            <div class="chart-container">
                <h3>Festplatten-Auslastung (/mnt/perry-nas)</h3>
                <canvas id="diskChart"></canvas>
            </div>
            <div class="chart-container">
                <h3>RAM-Auslastung</h3>
                <canvas id="ramChart"></canvas>
            </div>
        </div>

        <h2 style="margin-top: 40px;">Systemlast (Load Average)</h2>
        <div class="chart-container" style="max-width: 600px; margin: 20px auto;">
            <canvas id="loadChart"></canvas>
        </div>

    </div>

    <script>
        const API_URL = 'data.php';
        let cpuChart, diskChart, ramChart, loadChart;

        async function fetchSystemData() {
            try {
                const response = await fetch(API_URL);
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const data = await response.json();
                updateDashboard(data);
            } catch (error) {
                console.error("Fehler beim Abrufen der Systemdaten:", error);
                document.getElementById('hostname-box').innerHTML = 'Daten-Fehler';
            }
        }

        function getCpuColor(usage) {
            if (usage > 80) return '#e74c3c'; // Rot
            if (usage > 50) return '#f39c12'; // Orange/Gelb
            return '#2ecc71'; // Grün
        }

        function updateDashboard(data) {
            // 1. Statistische Boxen aktualisieren
            document.getElementById('hostname-box').innerHTML = '<strong>Hostname:</strong><br>' + data.hostname;
            document.getElementById('uptime-box').innerHTML = '<strong>Uptime:</strong><br>' + data.uptime;
            document.getElementById('timestamp-box').innerHTML = '<strong>Zuletzt aktualisiert:</strong><br>' + data.timestamp;

            // 2. Grafiken erstellen/aktualisieren
            
            // --- CPU (Balkendiagramm) ---
            const cpuUsage = data.cpu.usage_percent;
            document.getElementById('cpu-label').innerText = 'Prozessor-Auslastung (' + cpuUsage + '%)';
            
            const cpuData = {
                labels: ['CPU'],
                datasets: [{
                    label: 'Auslastung',
                    data: [cpuUsage],
                    backgroundColor: getCpuColor(cpuUsage),
                }]
            };
            if (cpuChart) cpuChart.destroy();
            cpuChart = new Chart(
                document.getElementById('cpuChart'), {
                    type: 'bar',
                    data: cpuData,
                    options: { 
                        indexAxis: 'y', // Macht den Balken horizontal
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: { legend: { display: false } },
                        scales: {
                            x: {
                                min: 0,
                                max: 100, // Wichtig: Skaliert von 0 bis 100
                                ticks: { stepSize: 25 },
                                title: { display: true, text: 'Prozent (%)' }
                            },
                            y: { display: false }
                        }
                    }
                }
            );

            // --- Festplatte (Disk Chart) ---
            const diskData = {
                labels: ['Belegt (' + data.disk.used + ' GB)', 'Frei (' + (data.disk.total - data.disk.used).toFixed(2) + ' GB)'],
                datasets: [{
                    data: [data.disk.used, data.disk.total - data.disk.used],
                    backgroundColor: ['#e74c3c', '#2ecc71'], 
                    hoverOffset: 4
                }]
            };
            if (diskChart) diskChart.destroy();
            diskChart = new Chart(
                document.getElementById('diskChart'), {
                    type: 'doughnut',
                    data: diskData,
                    options: { responsive: true, plugins: { legend: { position: 'bottom', labels: { color: '#333' } } } }
                }
            );

            // --- RAM (RAM Chart) ---
            const ramData = {
                labels: ['Belegt (' + data.ram.used + ' GB)', 'Frei (' + (data.ram.total - data.ram.used).toFixed(2) + ' GB)'],
                datasets: [{
                    data: [data.ram.used, data.ram.total - data.ram.used],
                    backgroundColor: ['#3498db', '#9b59b6'], 
                    hoverOffset: 4
                }]
            };
            if (ramChart) ramChart.destroy();
            ramChart = new Chart(
                document.getElementById('ramChart'), {
                    type: 'doughnut',
                    data: ramData,
                    options: { responsive: true, plugins: { legend: { position: 'bottom', labels: { color: '#333' } } } }
                }
            );

            // --- Last (Load Chart) ---
            const loadData = {
                labels: ['1 Min', '5 Min', '15 Min'],
                datasets: [{
                    label: 'Load Average',
                    data: [data.load['1min'], data.load['5min'], data.load['15min']],
                    backgroundColor: 'rgba(241, 196, 15, 0.5)', 
                    borderColor: '#f1c40f',
                    borderWidth: 1
                }]
            };
            if (loadChart) loadChart.destroy();
            loadChart = new Chart(
                document.getElementById('loadChart'), {
                    type: 'bar',
                    data: loadData,
                    options: { responsive: true, scales: { y: { beginAtZero: true } }, plugins: { legend: { display: false } } }
                }
            );
        }

        // Dashboard beim Laden einmal aktualisieren und dann alle 5 Sekunden
        fetchSystemData();
        setInterval(fetchSystemData, 5000); 
    </script>
</body>
</html>
EOF

# --- 4. Berechtigungen und Neustart ---
print_perry "Setze Berechtigungen und starte Webserver neu"
chown www-data:www-data /var/www/html/data.php
chmod 644 /var/www/html/data.php

# PHP-FPM Version muss ermittelt werden, um den Service neu zu starten
PHP_FPM_SERVICE=$(systemctl list-units --full --all | grep 'php[0-9]\.[0-9]-fpm.service' | awk '{print $1}' | head -n 1)

if [ -z "$PHP_FPM_SERVICE" ]; then
    print_error "PHP-FPM Service konnte nicht gefunden werden. Bitte manuell 'systemctl restart nginx' ausführen."
else
    systemctl restart nginx
    systemctl restart "$PHP_FPM_SERVICE"
    print_success "Nginx und PHP-FPM neu gestartet."
fi

print_success "CPU-Dashboard-Update (Balkendiagramm) abgeschlossen!"