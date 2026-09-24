# Serve the dashboard on localhost:8080 from the dist/ directory
# Usage: powershell -ExecutionPolicy Bypass -File tools/serve-dashboard.ps1

$port = 8080
$dir = Join-Path (Split-Path $PSScriptRoot -Parent) "dist"

Write-Host "Neon Touge RP4 - Live Dashboard Server"
Write-Host "Serving: $dir"
Write-Host "URL: http://localhost:${port}/dashboard.html"
Write-Host ""

# Start Python HTTP server
try {
    $env:PYTHONDONTWRITEBYTECODE = "1"
    python -m http.server $port --directory $dir --bind 0.0.0.0
} catch {
    Write-Host "Python not found. Trying py launcher..."
    py -m http.server $port --directory $dir --bind 0.0.0.0
}
