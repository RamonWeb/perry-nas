#!/bin/bash
# Perry-NAS Final LCARS Design Update Script
# Implementiert abgerundete Ecken, Neon-Glow und LCARS-Farben.
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

print_perry "Starte finales Star-Trek/LCARS-Design-Update."

# --- 1. PHP-Skript zur Datenerfassung (data.php) ---
print_perry "data.php bleibt unverändert."
# Der Code für data.php bleibt funktional unverändert.
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
    $stat1 = @file('/proc/stat');
    usleep(100000); 
    $stat2 = @file('/proc/stat');

    if ($stat1 === false || $stat2 === false) { return ['usage_percent' => 0]; }
    
    $parts1 = preg_split('/\s+/', $stat1[0]);
    $parts2 = preg_split('/\s+/', $stat2[0]);
    
    $idle_time_1 = (float)$parts1[4];
    $total_time_1 = 0;
    for ($j = 1; $j <= 10; $j++) { $total_time_1 += (float)$parts1[$j]; }
    
    $idle_time_2 = (float)$parts2[4];
    $total_time_2 = 0;
    for ($j = 1; $j <= 10; $j++) { $total_time_2 += (float)$parts2[$j]; }

    $delta_idle = $idle_time_2 - $idle_time_1;
    $delta_total = $total_time_2 - $total_time_1;
    
    if ($delta_total > 0) {
        $usage = 100 * (1 - $delta_idle / $delta_total);
    } else {
        $usage = 0;
    }
    
    $usage = max(0, min(100, $usage));

    return ['usage_percent' => round($usage, 1)];
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

# --- 2. Aktualisiertes HTML/JS Dashboard (index.php) ---
print_perry "Implementiere LCARS-Design und optimiere Chart-Farben."

cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>USS Perry-NAS Bridge</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        /* GLOBALES LCARS DESIGN */
        body {
            font-family: 'Arial', sans-serif;
            background-color: #000033; /* Tiefer Weltraum-Hintergrund */
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
            background: rgba(0, 0, 0, 0.2); 
            padding: 30px;
            border-radius: 20px; /* Stärkere Rundung */
            box-shadow: none; 
        }
        h1 {
            color: #FFD700; /* GOLD: Akzent für Titel */
            text-align: center;
            margin-bottom: 30px;
            text-shadow: 0 0 15px #00FFFF; /* Starker CYAN GLOW */
        }
        h2 {
            color: #00FFFF; /* CYAN: Wichtige Überschriften */
            border-bottom: 3px solid rgba(255, 102, 0, 0.8); /* LCARS Orange-Segment-Linie */
            padding-bottom: 10px;
            margin-top: 40px;
            text-shadow: 0 0 5px #00FFFF;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        /* LCARS Element-Boxen */
        .stat-box {
            background-color: rgba(255, 102, 0, 0.2); /* LCARS Orange/Apricot-Transparenz */
            color: #FFFFFF;
            padding: 15px;
            border-radius: 12px; /* Abgerundete LCARS-Kanten */
            text-align: center;
            border: 1px solid rgba(255, 102, 0, 0.5);
            box-shadow: 0 0 10px rgba(255, 102, 0, 0.5); /* Orange-Glow */
        }
        .stat-box strong {
            color: #FFD700; 
        }
        /* Chart Container als dunkel leuchtende Anzeigen */
        .chart-container {
            background: rgba(0, 255, 255, 0.1); /* Hellere, Cyan-Transparenz */
            padding: 20px;
            border-radius: 12px;
            border: 1px solid rgba(0, 255, 255, 0.5);
            box-shadow: 0 0 10px rgba(0, 255, 255, 0.5); /* Cyan-Glow */
            color: #FFFFFF; 
        }
        .chart-container h3 {
            color: #00FFFF; 
            text-align: center;
            text-shadow: 0 0 5px #00FFFF;
        }
        .grid-3 {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        #cpuChart {
            height: 200px !important; 
        }

        /* Anpassungen für Chart.js Tick-Labels, damit sie zum Design passen */
        .chart-container canvas {
            color: #FFFFFF !important; /* Wird von Chart.js eventuell ignoriert, aber versucht */
        }

    </style>
</head>
<body>
    <div class="container">
        <h1>🖖 USS Perry-NAS Bridge Interface</h1>
        
        <div class="stats-grid">
            <div class="stat-box" id="hostname-box"></div>
            <div class="stat-box" id="uptime-box"></div>
            <div class="stat-box" id="timestamp-box"></div>
        </div>

        <h2>CORE SYSTEMS STATUS</h2>
        <div class="grid-3">
            <div class="chart-container">
                <h3 id="cpu-label">CPU Core Status: NOMINAL</h3>
                <canvas id="cpuChart"></canvas>
            </div>
            <div class="chart-container">
                <h3>STORAGE INTEGRITY (/mnt/perry-nas)</h3>
                <canvas id="diskChart"></canvas>
            </div>
            <div class="chart-container">
                <h3>MEMORY ALLOCATION (RAM)</h3>
                <canvas id="ramChart"></canvas>
            </div>
        </div>

        <h2 style="margin-top: 40px;">SYSTEM LOAD VECTOR</h2>
        <div class="chart-container" style="max-width: 600px; margin: 20px auto;">
            <canvas id="loadChart"></canvas>
        </div>

    </div>

    <script>
        const API_URL = 'data.php';
        let cpuChart, diskChart, ramChart, loadChart;

        let prevDiskUsed = null;
        let prevRAMUsed = null;

        // Custom Chart.js Plugin für die Gauge (Nadel)
        const gaugeNeedle = {
            id: 'gaugeNeedle',
            afterDatasetDraw(chart, args, options) {
                const { ctx, data, chartArea: { left, top, right, bottom, width, height }, scales: { x, y } } = chart;
                ctx.save();
                
                // Hole den Wert
                const usage = data.datasets[0].data[0]; 
                
                // Berechnung des Winkels (0% = 225 Grad, 100% = -45 Grad)
                const angle = Math.PI + (Math.PI / 4) + (usage / 100 * (1.5 * Math.PI)); 
                
                const centerX = (left + right) / 2;
                const centerY = (top + bottom) / 2;
                const radius = Math.min(width, height) / 2;
                
                // Nadel zeichnen
                ctx.translate(centerX, centerY);
                ctx.rotate(angle);
                
                // Linie (Nadel)
                ctx.beginPath();
                ctx.moveTo(-5, 0); 
                ctx.lineTo(5, 0);
                ctx.lineTo(0, -radius * 0.7); 
                ctx.closePath();
                ctx.fillStyle = '#00FFFF'; // Cyan Nadel
                ctx.fill();

                // Nadel-Mittelpunkt (kleiner Kreis)
                ctx.beginPath();
                ctx.arc(0, 0, 5, 0, 2 * Math.PI);
                ctx.fillStyle = '#FFD700'; // Gold Mitte
                ctx.fill();
                
                ctx.restore();

                // Status-Text (Außerhalb der Canvas)
                let statusText = 'STATUS: NOMINAL (' + usage + '%)';
                let color = '#2ecc71';
                if (usage >= 80) {
                    statusText = 'ALERT! ALARMSTUFE ROT (' + usage + '%)';
                    color = '#e74c3c';
                } else if (usage >= 50) {
                    statusText = 'CAUTION! WARNUNG (' + usage + '%)';
                    color = '#f39c12';
                }

                ctx.font = 'bold 16px Arial';
                ctx.fillStyle = color;
                ctx.textAlign = 'center';
                ctx.shadowColor = color; // Glow für den Text
                ctx.shadowBlur = 5;
                ctx.fillText(statusText, centerX, bottom + 35);
                ctx.shadowBlur = 0; // Shadow zurücksetzen
            }
        };

        function getStatusText(usage) {
            if (usage >= 80) return 'CPU Core Status: ALERT';
            if (usage >= 50) return 'CPU Core Status: CAUTION';
            return 'CPU Core Status: NOMINAL';
        }

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

        function updateDashboard(data) {
            // 1. Statistische Boxen aktualisieren
            document.getElementById('hostname-box').innerHTML = '<strong>VESSEL:</strong><br>' + data.hostname;
            document.getElementById('uptime-box').innerHTML = '<strong>MISSION TIME:</strong><br>' + data.uptime;
            document.getElementById('timestamp-box').innerHTML = '<strong>LOG ENTRY:</strong><br>' + data.timestamp;

            // 2. Grafiken erstellen/aktualisieren
            
            // --- CPU (Star Trek Gauge) ---
            const cpuUsage = data.cpu.usage_percent;
            document.getElementById('cpu-label').innerText = getStatusText(cpuUsage);
            
            if (cpuChart) {
                cpuChart.data.datasets[0].data[3] = 100 - cpuUsage;
                cpuChart.update();
            } else {
                 const gaugeData = {
                    labels: ['Nominal (0-50%)', 'Caution (50-80%)', 'Alert (80-100%)', 'Wert'],
                    datasets: [{
                        data: [50, 30, 20, 100 - cpuUsage],
                        backgroundColor: ['#2ecc71', '#f39c12', '#e74c3c', 'rgba(0,0,0,0)'],
                        borderWidth: 0,
                    }]
                };

                cpuChart = new Chart(
                    document.getElementById('cpuChart'), {
                        type: 'doughnut',
                        data: gaugeData,
                        plugins: [gaugeNeedle],
                        options: { 
                            responsive: true,
                            circumference: 270, 
                            rotation: 225, 
                            cutout: '80%', 
                            plugins: { 
                                legend: { display: false },
                                tooltip: { enabled: false }
                            },
                            maintainAspectRatio: false,
                            layout: { padding: { bottom: 50 } }
                        }
                    }
                );
            }


            // --- Festplatte (Disk Chart) ---
            const currentDiskUsed = data.disk.used;
            
            if (currentDiskUsed !== prevDiskUsed) {
                const diskData = {
                    labels: ['USED (' + currentDiskUsed + ' GB)', 'AVAILABLE (' + (data.disk.total - currentDiskUsed).toFixed(2) + ' GB)'],
                    datasets: [{
                        data: [currentDiskUsed, data.disk.total - currentDiskUsed],
                        backgroundColor: ['#FF6600', '#00FFFF'], /* LCARS Orange für Used, Cyan für Available */
                        hoverOffset: 4
                    }]
                };
                
                if (diskChart) diskChart.destroy();
                diskChart = new Chart(
                    document.getElementById('diskChart'), {
                        type: 'doughnut',
                        data: diskData,
                        options: { 
                            responsive: true, 
                            plugins: { 
                                legend: { position: 'bottom', labels: { color: '#FFFFFF', font: { size: 14 } } }, 
                                tooltip: {
                                     callbacks: { label: (context) => context.label } 
                                }
                            }, 
                            animation: { animateScale: true } 
                        }
                    }
                );
                prevDiskUsed = currentDiskUsed;
            }


            // --- RAM (RAM Chart) ---
            const currentRAMUsed = data.ram.used;

            if (currentRAMUsed !== prevRAMUsed) {
                const ramData = {
                    labels: ['ALLOCATED (' + currentRAMUsed + ' GB)', 'FREE (' + (data.ram.total - currentRAMUsed).toFixed(2) + ' GB)'],
                    datasets: [{
                        data: [currentRAMUsed, data.ram.total - currentRAMUsed],
                        backgroundColor: ['#9b59b6', '#00FFFF'], /* LCARS Lila/Magenta für Allocated, Cyan für Free */
                        hoverOffset: 4
                    }]
                };

                if (ramChart) ramChart.destroy();
                ramChart = new Chart(
                    document.getElementById('ramChart'), {
                        type: 'doughnut',
                        data: ramData,
                        options: { 
                            responsive: true, 
                            plugins: { 
                                legend: { position: 'bottom', labels: { color: '#FFFFFF', font: { size: 14 } } },
                                tooltip: {
                                     callbacks: { label: (context) => context.label } 
                                } 
                            }, 
                            animation: { animateScale: true } 
                        }
                    }
                );
                prevRAMUsed = currentRAMUsed;
            }


            // --- Last (Load Chart) ---
            const loadData = {
                labels: ['1 MIN', '5 MIN', '15 MIN'],
                datasets: [{
                    label: 'LOAD AVERAGE',
                    data: [data.load['1min'], data.load['5min'], data.load['15min']],
                    backgroundColor: '#00FFFF', /* Reines Cyan */
                    borderColor: '#00FFFF',
                    borderWidth: 1,
                    barThickness: 30, // Dickere Balken
                }]
            };

            if (loadChart) {
                loadChart.data.datasets[0].data = [data.load['1min'], data.load['5min'], data.load['15min']];
                loadChart.update();
            } else {
                 loadChart = new Chart(
                    document.getElementById('loadChart'), {
                        type: 'bar',
                        data: loadData,
                        options: { 
                            responsive: true, 
                            scales: { 
                                y: { 
                                    beginAtZero: true, 
                                    grid: { color: 'rgba(255, 255, 255, 0.2)' }, 
                                    ticks: { color: '#FFD700', font: { size: 14 } } /* Gold-Ticks */
                                },
                                x: { 
                                    grid: { display: false }, 
                                    ticks: { color: '#FFFFFF', font: { size: 14 } } 
                                }
                            }, 
                            plugins: { 
                                legend: { display: false },
                                tooltip: {
                                     callbacks: { label: (context) => context.dataset.label + ': ' + context.formattedValue } 
                                }
                            } 
                        }
                    }
                );
            }
        }

        // Dashboard beim Laden einmal aktualisieren und dann alle 5 Sekunden
        fetchSystemData();
        setInterval(fetchSystemData, 5000); 
    </script>
</body>
</html>
EOF

# --- 3. Berechtigungen und Neustart ---
print_perry "Setze Berechtigungen und starte Webserver neu"
chown www-data:www-data /var/www/html/data.php
chmod 644 /var/www/html/data.php

PHP_FPM_SERVICE=$(systemctl list-units --full --all | grep 'php[0-9]\.[0-9]-fpm.service' | awk '{print $1}' | head -n 1)

if [ -z "$PHP_FPM_SERVICE" ]; then
    print_error "PHP-FPM Service konnte nicht gefunden werden. Bitte manuell 'systemctl restart nginx' ausführen."
else
    systemctl restart nginx
    systemctl restart "$PHP_FPM_SERVICE"
    print_success "Nginx und PHP-FPM neu gestartet."
fi

print_success "LCARS-Design-Update abgeschlossen. Die Bridge ist bereit!"