# Opens the game in a normal window for play-testing (desktop build of the current working tree).
# Re-run it to restart with the latest scripts, shaders and native build; the previous play
# window is closed first. Extra arguments go to the game, e.g.:
#   tools\play.ps1                      -> title screen
#   tools\play.ps1 scene=freeroam car=ferrari_f40 time=18 spawn=casino
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GameArgs)
. (Join-Path $PSScriptRoot "env.ps1")
$pidFile = Join-Path $NT_ROOT "build\play.pid"
if (Test-Path $pidFile) {
    $old = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($old) { Get-Process -Id $old -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false }
}
$godot = "$NT_TOOLCHAIN\godot\godot.exe"
if (-not (Test-Path $godot)) { $godot = $NT_GODOT }
# Import new/changed assets first so the window starts with everything current.
& $NT_GODOT --headless --path (Join-Path $NT_ROOT "godot") --import 2>&1 | Out-Null
$a = @("--path", (Join-Path $NT_ROOT "godot"), "--resolution", "1334x750")
if ($GameArgs) { $a += @("--") + $GameArgs }
$p = Start-Process -FilePath $godot -ArgumentList $a -PassThru
New-Item -ItemType Directory -Force (Split-Path $pidFile) | Out-Null
Set-Content -Path $pidFile -Value $p.Id -Encoding ascii
Write-Host "Game window started (pid $($p.Id)). Re-run tools\play.ps1 to restart with the latest changes."
