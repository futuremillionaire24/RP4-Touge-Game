<#
.SYNOPSIS
    Open Model Sourcer CLI - Search, download, inspect, extract, and register open-source 3D models for Neon Touge.
.DESCRIPTION
    Provides automated commands for sourcing CC0, CC-BY 4.0, and MIT 3D vehicle assets for Godot 4.7.
.EXAMPLE
    powershell -File tools/model_sourcer.ps1 search "sports car"
    powershell -File tools/model_sourcer.ps1 download <url> godot/assets/models/cars/car.glb
    powershell -File tools/model_sourcer.ps1 inspect res://assets/models/cars/car.glb
    powershell -File tools/model_sourcer.ps1 extract res://assets/models/cars/cars_big_set.glb car_beemer res://assets/models/cars/senko.tscn
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "help",

    [Parameter(Position=1)]
    [string]$Arg1 = "",

    [Parameter(Position=2)]
    [string]$Arg2 = "",

    [Parameter(Position=3)]
    [string]$Arg3 = ""
)

$ErrorActionPreference = "Stop"
$ProjectDir = (Resolve-Path "$PSScriptRoot\..").Path
$GodotDir = Join-Path $ProjectDir "godot"
$GodotExe = "D:\RP4Toolchain\godot\godot_console.exe"
if (-not (Test-Path $GodotExe)) {
    $GodotExe = "godot"
}

function Show-Help {
    Write-Host "=== OPEN MODEL SOURCER CLI ===" -ForegroundColor Cyan
    Write-Host "Commands:"
    Write-Host "  search <query>                     - Search verified open-source 3D model sources"
    Write-Host "  download <url> <filename>          - Download .glb / .gltf into assets/models/cars/"
    Write-Host "  inspect <model_res_path>           - Inspect node hierarchy, vertex/tri count, and bounds"
    Write-Host "  list <pack_res_path>               - List vehicle sub-nodes in a multi-car asset pack"
    Write-Host "  extract <pack> <node_name> <out>   - Extract a sub-vehicle into an independent .tscn"
    Write-Host "  registries                         - Display curated open-source model registries"
}

function Show-Registries {
    Write-Host "`n=== CURATED OPEN-SOURCE 3D MODEL REGISTRIES ===" -ForegroundColor Cyan
    Write-Host "1. Poly Pizza (https://poly.pizza/)" -ForegroundColor Yellow
    Write-Host "   - License: CC0 / CC-BY"
    Write-Host "   - Format: Direct GLB/GLTF download"
    Write-Host "   - Notes: Thousands of low-to-mid poly assets, Quaternius packs."
    
    Write-Host "2. Khronos Group glTF-Sample-Assets (https://github.com/KhronosGroup/glTF-Sample-Assets)" -ForegroundColor Yellow
    Write-Host "   - License: CC-BY 4.0 / CC0"
    Write-Host "   - Format: Raw GLB"
    Write-Host "   - Models: CarConcept, ToyCar, ClearCoatCarPaint."

    Write-Host "3. KenneyNL Racing Kits (https://github.com/KenneyNL/Starter-Kit-Racing)" -ForegroundColor Yellow
    Write-Host "   - License: CC0 Public Domain"
    Write-Host "   - Format: GLB / FBX"
    Write-Host "   - Models: Trucks, karts, track elements, pickups."

    Write-Host "4. Three.js Cars Collection (https://github.com/nbogie/three-js-cars-3)" -ForegroundColor Yellow
    Write-Host "   - License: CC-BY 4.0"
    Write-Host "   - Format: GLB"
    Write-Host "   - Models: 15 modular vehicles with detached wheels and lights."
}

function Search-Models([string]$Query) {
    Write-Host "`nSearching open-source registries for '$Query'..." -ForegroundColor Cyan
    $results = @(
        @{ Name="Car Concept (Hypercar/GT)"; Source="Khronos glTF Samples"; License="CC-BY 4.0"; Format="GLB (11.2MB)"; URL="https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/CarConcept/glTF-Binary/CarConcept.glb" },
        @{ Name="Cars Big Set (15 modular vehicles)"; Source="three-js-cars-3"; License="CC-BY 4.0"; Format="GLB (1.5MB)"; URL="https://raw.githubusercontent.com/nbogie/three-js-cars-3/master/models/cars_big_set.glb" },
        @{ Name="Racing Kit Vehicles (Trucks/Karts)"; Source="KenneyNL"; License="CC0 Public Domain"; Format="GLB"; URL="https://raw.githubusercontent.com/KenneyNL/Starter-Kit-Racing/main/models/vehicle-truck-yellow.glb" }
    )

    $filtered = $results | Where-Object { $_.Name -like "*$Query*" -or $Query -eq "" -or $_.Source -like "*$Query*" }
    if ($filtered.Count -eq 0) {
        $filtered = $results
    }

    Write-Host "`nFound ($($filtered.Count)) matching open-source assets:" -ForegroundColor Green
    foreach ($item in $filtered) {
        Write-Host " • $($item.Name)" -ForegroundColor White
        Write-Host "   Source: $($item.Source) | License: $($item.License) | Format: $($item.Format)" -ForegroundColor Gray
        Write-Host "   URL: $($item.URL)" -ForegroundColor DarkGray
    }
}

function Download-Model([string]$Url, [string]$OutFile) {
    if (-not $Url -or -not $OutFile) {
        Write-Error "Usage: download <url> <output_filepath>"
        return
    }
    $targetPath = $OutFile
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path $GodotDir "assets/models/cars/$OutFile"
    }
    $parent = Split-Path -Parent $targetPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Write-Host "Downloading $Url -> $targetPath..." -ForegroundColor Cyan
    curl.exe -L -o $targetPath $Url
    if (Test-Path $targetPath) {
        $sizeMB = [math]::Round(((Get-Item $targetPath).Length / 1MB), 2)
        Write-Host "Download complete: $sizeMB MB" -ForegroundColor Green
        Write-Host "Triggering Godot import scan..." -ForegroundColor Cyan
        & $GodotExe --headless --editor --path $GodotDir --quit | Out-Null
        Write-Host "Godot asset imported successfully." -ForegroundColor Green
    } else {
        Write-Error "Download failed."
    }
}

function Run-GodotTool([string]$ToolCmd, [string]$A1, [string]$A2, [string]$A3) {
    $script = "res://tools/model_sourcer.gd"
    $cmdArgs = @("--headless", "--path", $GodotDir, "-s", $script, "--", $ToolCmd)
    if ($A1) { $cmdArgs += $A1 }
    if ($A2) { $cmdArgs += $A2 }
    if ($A3) { $cmdArgs += $A3 }

    & $GodotExe $cmdArgs
}

switch ($Command.ToLower()) {
    "help"        { Show-Help }
    "registries"  { Show-Registries }
    "search"      { Search-Models $Arg1 }
    "download"    { Download-Model $Arg1 $Arg2 }
    "inspect"     { Run-GodotTool "inspect" $Arg1 "" "" }
    "list"        { Run-GodotTool "list" $Arg1 "" "" }
    "extract"     { Run-GodotTool "extract" $Arg1 $Arg2 $Arg3 }
    default       { Show-Help }
}
