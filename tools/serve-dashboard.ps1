# Serve the live perfection-loop dashboard on localhost:8080 from the dist/ directory.
# Usage: powershell -ExecutionPolicy Bypass -File tools/serve-dashboard.ps1
# The page polls dist/progress/{state.json, pieces/NN.json, feed.jsonl}; see tools/perfection/ORCHESTRATION.md.

$port = 8080
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root "dist"
New-Item -ItemType Directory -Force (Join-Path $dir "progress\pieces") | Out-Null
$page = Join-Path $PSScriptRoot "dashboard\dashboard.html"
Copy-Item $page (Join-Path $dir "dashboard.html") -Force
Copy-Item $page (Join-Path $dir "index.html") -Force

Write-Host "Neon Touge RP4 - Live Dashboard Server"
Write-Host "Serving: $dir"
Write-Host "URL: http://localhost:${port}/dashboard.html"
Write-Host ""

$env:PYTHONDONTWRITEBYTECODE = "1"
. (Join-Path $PSScriptRoot "env.ps1")
python -m http.server $port --directory $dir --bind 0.0.0.0
