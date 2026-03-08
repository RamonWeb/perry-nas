#!/bin/bash
# Perry-NAS Pip-Boy Theme Update Script - DUAL DISK (v2)
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

print_perry "Update für /mnt/perry-nas und /mnt/perry-nas-2 wird installiert..."

# --- 1. PHP-Skript zur Datenerfassung (data.php) ---
cat > /var/www/html/data.php << 'EOF'
<?php
header('Content-Type: application/json');

function get_cpu_temp() {
    $temp_raw = @file_get_contents('/sys/class/thermal/thermal_zone0/temp');
    if ($temp_raw === false) {
        $temp_output = shell_exec('vcgencmd measure_temp 2>&1');
        if (preg_match('/temp=([0-9.]+)\'C/', $temp_output, $matches)) {
            return ['temp_c' => (float)$matches[1]];
        }
        return ['temp_c' => 'N/A'];
    }
    return ['temp_c' => round((int)trim($temp_raw) / 1000, 1)];
}

function get_disk_usage($path) {
    if (!is_dir($path)) return ['error' => 'Not mounted', 'path' => $path];
    $total = disk_total_space($path);
    $free = disk_free_space($path);
    if ($total <= 0) return ['error' => 'Empty or Protected', 'path' => $path];
    $used = $total - $free;
    return [
        'total' => round($total / (1024*1024*1024), 2),
        'used' => round($used / (1024*1024*1024), 2),
        'used_percent' => round(($used / $total) * 100, 1)
    ];
}

function get_ram_usage() {
    $free_output = shell_exec('free -b | grep Mem:');
    $parts = preg_split('/\s+/', $free_output);
    $total = (float)$parts[1];
    $used = (float)$parts[2];
    return [
        'total' => round($total / (1024*1024*1024), 2),
        'used' => round($used / (1024*1024*1024), 2),
        'used_percent' => round(($used / $total) * 100, 1)
    ];
}

$status = [
    'hostname' => trim(shell_exec('hostname')),
    'uptime' => trim(shell_exec('uptime -p')),
    'disk1' => get_disk_usage('/mnt/perry-nas'),
    'disk2' => get_disk_usage('/mnt/perry-nas-2'),
    'ram' => get_ram_usage(),
    'load' => sys_getloadavg(),
    'cpu' => ['usage_percent' => round(100 - (float)shell_exec("top -bn1 | grep 'Cpu(s)' | awk '{print $8}'"), 1)],
    'temp' => get_cpu_temp(),
    'timestamp' => date('Y-m-d H:i:s')
];

echo json_encode($status);
?>
EOF

# --- 2. Aktualisiertes HTML/JS Dashboard (index.php) ---
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <title>Perry-NAS Terminal 3000</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: 'Courier New', monospace; background-color: #000; color: #39ff14; padding: 20px; display: flex; flex-direction: column; align-items: center; }
        .container { width: 100%; max-width: 1100px; border: 5px solid #39ff14; padding: 30px; box-shadow: 0 0 50px rgba(57, 255, 20, 0.4); }
        h1, h2 { text-align: center; text-shadow: 0 0 10px #39ff14; border-bottom: 2px solid #39ff14; padding-bottom: 10px; }
        .stats-grid, .grid-4 { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .stat-box, .chart-container { border: 1px solid #39ff14; padding: 15px; box-shadow: 0 0 5px #39ff14; }
        .progress-bar { height: 20px; background: #000; border: 1px solid #39ff14; position: relative; margin-top: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: #39ff14; width: 0%; transition: width 0.8s ease-in-out; }
        .progress-label { position: absolute; width: 100%; text-align: center; top: 0; color: #000; font-weight: bold; font-size: 0.8em; line-height: 20px; z-index: 2; text-shadow: 0 0 2px #39ff14; }
        .temp-display { font-size: 1.4em; text-align: center; margin: 10px 0; font-weight: bold; border: 1px dashed #39ff14; padding: 5px; }
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

        <h2>:: CORE SYSTEMS & STORAGE</h2>
        <div class="grid-4">
            <div class="chart-container">
                <h3>CPU LOAD</h3>
                <div class="temp-display" id="temp-info">-- °C</div>
                <div class="progress-bar"><div class="progress-fill" id="cpu-fill"></div><span class="progress-label" id="cpu-percent">0%</span></div>
            </div>
            <div class="chart-container">
                <h3>MEMORY (RAM)</h3>
                <p id="ram-info">Lade...</p>
                <div class="progress-bar"><div class="progress-fill" id="ram-fill"></div><span class="progress-label" id="ram-percent">0%</span></div>
            </div>
            <div class="chart-container">
                <h3>DISK 1 (MAIN)</h3>
                <p id="disk1-info">Lade...</p>
                <div class="progress-bar"><div class="progress-fill" id="disk1-fill"></div><span class="progress-label" id="disk1-percent">0%</span></div>
            </div>
            <div class="chart-container">
                <h3>DISK 2 (NAS-2)</h3>
                <p id="disk2-info">Lade...</p>
                <div class="progress-bar"><div class="progress-fill" id="disk2-fill"></div><span class="progress-label" id="disk2-percent">0%</span></div>
            </div>
        </div>
        <div style="width: 100%; height: 200px;"><canvas id="loadChart"></canvas></div>
    </div>

    <script>
        let loadChart;
        async function update() {
            try {
                const res = await fetch('data.php');
                const d = await res.json();
                
                document.getElementById('hostname-box').innerHTML = '<b>HOST:</b> ' + d.hostname.toUpperCase();
                document.getElementById('uptime-box').innerHTML = '<b>UPTIME:</b> ' + d.uptime.toUpperCase();
                document.getElementById('timestamp-box').innerHTML = '<b>LOG: