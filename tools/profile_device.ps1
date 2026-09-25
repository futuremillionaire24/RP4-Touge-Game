# Performance audit on the Retroid Pocket 4 Pro (and optionally the desktop baseline).
# Installs dist/NeonTougeRP4.apk, launches the in-game audit (scene=perf_audit, see
# godot/scripts/core/perf_audit.gd) through Godot's "command_line_params" intent extra, collects the
# PERFJSON lines from logcat and writes build/qa/perf/report.md (desktop vs RP4).
#   tools\profile_device.ps1 [-Desktop] [-NoInstall] [-Settle 8] [-Sample 15] [-Only day_parked,night_parked]
param([switch]$Desktop, [switch]$NoInstall, [switch]$Ablate, [int]$Settle = 8, [int]$Sample = 15, [string]$Only = "", [string]$Spawn = "garage_port", [string]$Car = "golf_gti")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "env.ps1")
$out = Join-Path $NT_ROOT "build\qa\perf"
New-Item -ItemType Directory -Force $out | Out-Null
$pkg = "com.neontouge.rp4"
$auditArgs = @("scene=perf_audit", "settle=$Settle", "sample=$Sample", "spawn=$Spawn", "car=$Car")
if ($Only) { $auditArgs += "only=$Only" }
# -Ablate: one parked scene, each feature switched off in turn (GPU cost per feature).
if ($Ablate) { $auditArgs += "ablate=1" }

function Parse-Perf([string[]]$lines) {
    $lines | Where-Object { $_ -match "PERFJSON (\{.*\})" } | ForEach-Object { ([regex]::Match($_, "PERFJSON (\{.*\})")).Groups[1].Value | ConvertFrom-Json }
}

# ---- Desktop baseline --------------------------------------------------------------------------
$desk = @()
if ($Desktop) {
    Write-Host "== desktop audit"
    $log = & $NT_GODOT --path (Join-Path $NT_ROOT "godot") --resolution 1334x750 -- @auditArgs 2>&1 | Out-String
    $desk = @(Parse-Perf ($log -split "`n"))
    $desk | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $out "desktop.json")
}

# ---- RP4 ---------------------------------------------------------------------------------------
$dev = (adb devices | Select-String "\tdevice$" | Select-Object -First 1)
if (-not $dev) { throw "No Android device connected (adb devices)" }
if (-not $NoInstall) {
    Write-Host "== installing APK"
    adb install -r (Join-Path $NT_ROOT "dist\NeonTougeRP4.apk") | Out-Host
}
# Keep the panel on while profiling (a sleeping screen pauses the game), wake and unlock.
adb shell svc power stayon true | Out-Null
adb shell input keyevent 224 | Out-Null
Start-Sleep -Milliseconds 500
adb shell wm dismiss-keyguard | Out-Null
adb shell input keyevent 82 | Out-Null
adb shell am force-stop $pkg | Out-Null
adb logcat -c
# Android has no command line: the game reads (and deletes) launch_args.txt from its external
# files folder on start (godot/scripts/core/launch_args.gd).
$argFile = "/sdcard/Android/data/$pkg/files/launch_args.txt"
adb shell mkdir -p "/sdcard/Android/data/$pkg/files" | Out-Null
adb shell "echo '$($auditArgs -join ' ')' > $argFile" | Out-Null
Write-Host "== launching audit on the RP4 ($($auditArgs -join ' '))"
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
$deadline = (Get-Date).AddMinutes(20)
$lines = @()
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    $lines = adb logcat -d -s godot:* | Out-String -Stream
    $n = @($lines | Select-String "PERFJSON").Count
    Write-Host ("  {0:HH:mm:ss} scenarios done: {1}" -f (Get-Date), $n)
    if ($lines | Select-String "PERF audit done|world never finished") { break }
}
adb shell svc power stayon false | Out-Null
$lines | Set-Content -Encoding utf8 (Join-Path $out "device_logcat.txt")
$rp4 = @(Parse-Perf $lines)
$rp4 | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $out "device.json")
$thermal = adb shell dumpsys thermalservice 2>$null | Select-String "Temperature\{mValue=" | Select-Object -First 3

# ---- Report ------------------------------------------------------------------------------------
$rows = @("| Scenario | Platform | fps avg | 1% low | frame max ms | GPU ms | CPU ms | draws | shadow draws | prims | VRAM MB | tier / scale |", "|---|---|---|---|---|---|---|---|---|---|---|---|")
foreach ($set in @(@("RP4", $rp4), @("Desktop", $desk))) {
    foreach ($r in $set[1]) {
        $rows += "| $($r.tag) | $($set[0]) | $($r.fps_avg) | $($r.fps_low1) | $($r.frame_ms_max) | $($r.gpu_ms) | $($r.cpu_ms) | $($r.draw_calls) | $($r.shadow_draw_calls) | $([math]::Round($r.primitives / 1000))k | $($r.video_mem_mb) | $($r.governor_tier) / $($r.render_scale) |"
    }
}
$report = "# Performance audit $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n`n" + ($rows -join "`n") + "`n`nThermal: $($thermal -join '; ')`n"
$report | Set-Content -Encoding utf8 (Join-Path $out "report.md")
Write-Host $report
if ($rp4.Count -eq 0) { Write-Warning "No results from the device - see build\qa\perf\device_logcat.txt" }
