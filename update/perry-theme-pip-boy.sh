#!/bin/bash
# Perry-NAS Pip-Boy Theme Update Script - Inklusive CPU-Temperatur
set -e

# Farbdefinitionen
GREEN='\033[0;32m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_perry() { echo -e "${PURPLE}[PERRY-NAS]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Root Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen: sudo $0"
    exit 1
fi

print_perry "Starte Pip-Boy-Terminal-Design-Update (inkl. CPU-Temperatur)."

# --- 1. PHP-Skript zur Datenerfassung (data.php) ---
print_perry "data.php wird um die Temperaturerfassung erweitert."

cat > /var/www/html/data.php << 'EOF'
<?php
header('Content-Type: application/json');

// Funktion zum Abrufen der CPU-Temperatur
function get_cpu_temp() {
    $temp_raw = @file_get_contents('/sys/class/thermal/thermal_zone0/temp');
    
    if ($temp_raw === false) {
        // Fallback für Raspberry Pi (Ältere OS-Versionen oder Pi 4/3)
        $temp_output = shell_exec('vcgencmd measure_temp 2>&1');
        if (preg_match('/temp=([0-9.]+)\'C/', $temp_output, $matches)) {
            return ['temp_c' => (float)$matches[1]];
        }
        return ['temp_c' => 'N/A'];
    }
    
    // Standard: Wert ist in Millidegree Celsius
    $temp_c = round((int)trim($temp_raw) / 1000, 1);
    
    return ['temp_c' => $temp_c];
}

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
    'temp' => get_cpu_temp(), // NEU: CPU-Temperatur
    'timestamp' => date('Y-m-d H:i:s')
];

echo json_encode($status, JSON_PRETTY_PRINT);
?>
EOF

# --- 2. Aktualisiertes HTML/JS Dashboard (index.php) ---
print_perry "Implementiere Temperaturanzeige im Frontend."

cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Perry-NAS Terminal 3000</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        /* PIP-BOY MONOCHROM DESIGN */
        body {
            font-family: 'Courier New', monospace; 
            background-color: #000000; 
            color: #39ff14; 
            margin: 0;
            padding: 20px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .container {
            width: 100%;
            max-width: 1000px;
            background: #000000; 
            padding: 30px;
            border-radius: 0;
            border: 5px solid #39ff14; 
            box-shadow: 0 0 50px rgba(57, 255, 20, 0.4); 
        }
        h1 {
            color: #39ff14; 
            text-align: center;
            margin-bottom: 20px;
            text-shadow: 0 0 10px #39ff14;
            border-bottom: 2px solid #39ff14;
            padding-bottom: 10px;
        }
        h2 {
            color: #39ff14; 
            border-bottom: 1px solid #39ff14;
            padding-bottom: 5px;
            margin-top: 30px;
            text-shadow: 0 0 5px #39ff14;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .stat-box {
            background-color: transparent; 
            color: #39ff14;
            padding: 10px;
            border-radius: 0;
            text-align: left;
            border: 1px solid #39ff14;
            box-shadow: 0 0 5px #39ff14;
        }
        .stat-box strong {
            color: #39ff14; 
            display: block;
            text-decoration: underline;
            margin-bottom: 5px;
        }
        .chart-container {
            background: #000000; 
            padding: 15px;
            border-radius: 0;
            border: 1px dashed #39ff14; 
            box-shadow: 0 0 5px #39ff14; 
            color: #39ff14; 
            min-height: 180px; 
        }
        .chart-container h3 {
            color: #39ff14; 
            text-align: center;
            text-shadow: 0 0 5px #39ff14;
            margin-bottom: 15px;
        }
        /* Neue Klasse für Temperaturanzeige */
        .temp-display {
            text-align: center;
            font-size: 1.2em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .grid-3 {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        /* Progress Bar Styling */
        .progress-bar-wrapper {
            margin-top: 10px;
            margin-bottom: 10px;
        }
        .progress-bar {
            height: 25px;
            background-color: #000000;
            border: 1px solid #39ff14;
            box-shadow: inset 0 0 5px #39ff14;
            position: relative;
        }
        .progress-fill {
            height: 100%;
            background-color: #39ff14;
            box-shadow: 0 0 10px #39ff14;
            transition: width 0.5s ease-out; 
            width: 0%; 
        }
        .progress-label {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: #000000; 
            text-shadow: 1px 1px 0 #39ff14; 
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>[PERRY-NAS] >> SYSTEM STATUS_REPORT</h1>
        
        <div class="stats-grid">
            <div class="stat-box" id="hostname-box"></div>
            <div class="stat-box" id="uptime-box"></div>
            <div class="stat-box" id="timestamp-box"></div>
        </div>

        <h2>:: CORE SYSTEMS</h2>
        <div class="grid-3">
            <div class="chart-container">
                <h3 id="cpu-label">CPU LOAD</h3>
                <div class="temp-display" id="temp-info"></div>
                
                <div class="progress-bar-wrapper">
                    <div class="progress-bar">
                        <div class="progress-fill" id="cpu-fill"></div>
                        <span class="progress-label" id="cpu-percent"></span>
                    </div>
                </div>
            </div>
            
            <div class="chart-container">
                <h3>STORAGE ALLOCATION (/MNT/PERRY-NAS)</h3>
                <p id="disk-info"></p>
                <div class="progress-bar-wrapper">
                    <div class="progress-bar">
                        <div class="progress-fill" id="disk-fill"></div>
                        <span class="progress-label" id="disk-percent"></span>
                    </div>
                </div>
            </div>
            
            <div class="chart-container">
                <h3>MEMORY ALLOCATION (RAM)</h3>
                <p id="ram-info"></p>
                <div class="progress-bar-wrapper">
                    <div class="progress-bar">
                        <div class="progress-fill" id="ram-fill"></div>
                        <span class="progress-label" id="ram-percent"></span>
                    </div>
                </div>
            </div>
        </div>

        <h2 style="margin-top: 40px;">:: PROCESS LOAD HISTORY (CHART)</h2>
        <div class="chart-container" style="max-width: 600px; margin: 20px auto;">
            <canvas id="loadChart"></canvas>
        </div>

    </div>

    <script>
        const API_URL = 'data.php';
        let loadChart;

        let prevDiskUsed = null;
        let prevRAMUsed = null;

        // Hilfsfunktion zum Aktualisieren des Balkens
        function updateProgressBar(fillId, percentId, percent, labelText = null) {
            const fill = document.getElementById(fillId);
            const percentSpan = document.getElementById(percentId);
            
            fill.style.width = percent + '%';
            
            // Anpassung der Farbe bei kritischen Werten
            const criticalColor = '#FF0000';
            const cautionColor = '#FFFF00';
            const normalColor = '#39ff14';

            if (percent >= 80) {
                 fill.style.backgroundColor = criticalColor; 
                 fill.style.boxShadow = '0 0 10px ' + criticalColor;
            } else if (percent >= 50) {
                 fill.style.backgroundColor = cautionColor; 
                 fill.style.boxShadow = '0 0 10px ' + cautionColor;
            } else {
                 fill.style.backgroundColor = normalColor; 
                 fill.style.boxShadow = '0 0 10px ' + normalColor;
            }

            // Textfarbe im Label anpassen
            if (percent > 10) { 
                 const textColor = (percent >= 50) ? '#000000' : normalColor;
                 const textShadow = (percent >= 50) ? '1px 1px 0 ' + normalColor : '1px 1px 0 #000000';
                 percentSpan.style.color = textColor;
                 percentSpan.style.textShadow = textShadow;

            } else {
                 percentSpan.style.color = normalColor;
                 percentSpan.style.textShadow = 'none';
            }

            percentSpan.innerText = labelText || (percent.toFixed(1) + '%');
        }

        function updateTempDisplay(temp, elementId) {
            const tempElement = document.getElementById(elementId);
            const normalColor = '#39ff14';
            let displayColor = normalColor;
            let displayGlow = '0 0 5px ' + normalColor;
            
            if (temp === 'N/A') {
                tempElement.innerText = 'TEMP: N/A';
            } else {
                tempElement.innerText = 'TEMP: ' + temp + ' °C';
                
                if (temp > 75) {
                    displayColor = '#FF0000'; // Rot: Alarm
                    displayGlow = '0 0 5px ' + displayColor;
                } else if (temp > 60) {
                    displayColor = '#FFFF00'; // Gelb: Warnung
                    displayGlow = '0 0 5px ' + displayColor;
                }
            }
            
            tempElement.style.color = displayColor;
            tempElement.style.textShadow = displayGlow;
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
                document.getElementById('hostname-box').innerHTML = '>> DATA ERROR <<';
            }
        }

        function updateDashboard(data) {
            // 1. Statistische Boxen aktualisieren
            document.getElementById('hostname-box').innerHTML = '<strong>HOST NAME:</strong><br>' + data.hostname.toUpperCase();
            document.getElementById('uptime-box').innerHTML = '<strong>MISSION TIME:</strong><br>' + data.uptime.toUpperCase();
            document.getElementById('timestamp-box').innerHTML = '<strong>LAST LOG:</strong><br>' + data.timestamp.toUpperCase();

            // 2. Grafiken / Balken aktualisieren
            
            // --- CPU (Dynamisch) ---
            const cpuUsage = data.cpu.usage_percent;
            const cpuTemp = data.temp.temp_c;
            
            document.getElementById('cpu-label').innerText = 'CPU LOAD: ' + cpuUsage.toFixed(1) + '%';
            updateProgressBar('cpu-fill', 'cpu-percent', cpuUsage);
            
            // NEU: Temperaturanzeige aktualisieren
            updateTempDisplay(cpuTemp, 'temp-info');
            
            // --- Festplatte (Stabil) ---
            const currentDiskUsed = data.disk.used;
            if (currentDiskUsed !== prevDiskUsed) {
                 const diskLabel = `USED: ${currentDiskUsed} GB | TOTAL: ${data.disk.total.toFixed(2)} GB`;
                 document.getElementById('disk-info').innerText = diskLabel;
                 updateProgressBar('disk-fill', 'disk-percent', data.disk.used_percent);
                 prevDiskUsed = currentDiskUsed;
            }

            // --- RAM (Stabil) ---
            const currentRAMUsed = data.ram.used;
            if (currentRAMUsed !== prevRAMUsed) {
                const ramLabel = `USED: ${currentRAMUsed} GB | TOTAL: ${data.ram.total.toFixed(2)} GB`;
                document.getElementById('ram-info').innerText = ramLabel;
                updateProgressBar('ram-fill', 'ram-percent', data.ram.used_percent);
                prevRAMUsed = currentRAMUsed;
            }


            // --- Last (Load Chart) ---
            const loadData = {
                labels: ['1 MIN', '5 MIN', '15 MIN'],
                datasets: [{
                    label: 'LOAD AVERAGE',
                    data: [data.load['1min'], data.load['5min'], data.load['15min']],
                    backgroundColor: '#39ff14', 
                    borderColor: '#39ff14',
                    borderWidth: 1,
                    barThickness: 20, 
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
                                    grid: { color: 'rgba(57, 255, 20, 0.2)' }, 
                                    ticks: { color: '#39ff14', font: { size: 14 } } 
                                },
                                x: { 
                                    grid: { display: false }, 
                                    ticks: { color: '#39ff14', font: { size: 14 } } 
                                }
                            }, 
                            plugins: { 
                                legend: { display: false },
                                tooltip: {
                                    backgroundColor: 'rgba(0, 0, 0, 0.9)',
                                    borderColor: '#39ff14',
                                    borderWidth: 1,
                                    titleColor: '#39ff14',
                                    bodyColor: '#39ff14'
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

print_success "Pip-Boy-Design-Update abgeschlossen. Temperaturüberwachung ist aktiviert."