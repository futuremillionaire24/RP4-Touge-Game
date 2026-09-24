# Builds the Godot-independent simulation core with llvm-mingw and runs the doctest suite.
param([string]$Filter = "", [switch]$Release)
$ErrorActionPreference = "Stop"
$env:PATH = "D:\RP4Toolchain\llvm-mingw\bin;$env:PATH"
$native = Join-Path $PSScriptRoot "..\native" | Resolve-Path
$out = Join-Path $native "build_tests"
New-Item -ItemType Directory -Force $out | Out-Null
$sources = @(Get-ChildItem (Join-Path $native "src\sim") -Filter *.cpp) + @(Get-ChildItem (Join-Path $native "src\sim\world") -Filter *.cpp) + @(Get-ChildItem (Join-Path $native "tests") -Filter *.cpp)
$objs = @()
foreach ($s in $sources) {
    $o = Join-Path $out ($s.BaseName + ".o")
    if (-not (Test-Path $o) -or (Get-Item $o).LastWriteTime -lt $s.LastWriteTime -or (Get-ChildItem (Join-Path $native "src\sim") -Filter *.h -Recurse | Where-Object { $_.LastWriteTime -gt (Get-Item $o).LastWriteTime })) {
        & clang++ -std=c++17 -O2 -g -Wall -Wextra -I (Join-Path $native "src") -I (Join-Path $native "tests") -c $s.FullName -o $o
        if ($LASTEXITCODE -ne 0) { throw "compile failed: $($s.Name)" }
    }
    $objs += $o
}
$exe = Join-Path $out "nt_tests.exe"
& clang++ -o $exe @objs -static
if ($LASTEXITCODE -ne 0) { throw "link failed" }
$args = @()
if ($Filter) { $args += "--test-case=$Filter" }
& $exe @args
exit $LASTEXITCODE
