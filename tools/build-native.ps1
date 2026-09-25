# Builds the GDExtension. -Platform windows|android|all, -Target template_debug|template_release|both
param([string]$Platform = "all", [string]$Target = "both", [int]$Jobs = 0)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "env.ps1")
if ($Jobs -le 0) { $Jobs = [Environment]::ProcessorCount }
$targets = if ($Target -eq "both") { @("template_debug", "template_release") } else { @($Target) }
$platforms = if ($Platform -eq "all") { @("windows", "android") } else { @($Platform) }
Push-Location (Join-Path $NT_ROOT "native")
# A running game (tools\play.ps1) keeps the Windows DLL loaded. Windows allows renaming a loaded
# DLL, so move it aside and let the linker write a fresh one; the game picks it up on restart.
$bin = Join-Path $NT_ROOT "godot\native\bin"
# (-Filter "*.dll" would also match "*.dll.old..." - Windows wildcard quirk - so match exactly.)
$files = @(Get-ChildItem $bin -File -ErrorAction SilentlyContinue)
foreach ($f in $files | Where-Object { $_.Name -like "*.dll.old*" }) { try { Remove-Item $f.FullName -Force -ErrorAction Stop } catch {} }
foreach ($f in $files | Where-Object { $_.Extension -eq ".dll" }) {
    try { [IO.File]::Open($f.FullName, 'Open', 'ReadWrite', 'None').Close() }
    catch { Rename-Item $f.FullName "$($f.Name).old$([DateTime]::Now.Ticks)" }
}
try {
    foreach ($p in $platforms) {
        foreach ($t in $targets) {
            $args = @("-m", "SCons", "-j$Jobs", "platform=$p", "target=$t")
            if ($p -eq "windows") { $args += @("use_mingw=yes", "use_llvm=yes", "mingw_prefix=$($NT_TOOLCHAIN -replace '\\','/')/llvm-mingw") }
            if ($p -eq "android") { $args += @("arch=arm64", "ANDROID_HOME=$($env:ANDROID_HOME -replace '\\','/')") }
            Write-Host "== scons $p $t"
            & python @args
            if ($LASTEXITCODE -ne 0) { throw "scons failed for $p $t" }
        }
    }
} finally { Pop-Location }
