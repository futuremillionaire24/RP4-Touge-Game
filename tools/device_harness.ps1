# Hardware harness for Retroid Pocket 4 Pro over ADB
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Action,
    [Parameter(Position=1)]
    [string]$Target = "",
    [Parameter(Position=2)]
    [string]$Extra = ""
)

. (Join-Path $PSScriptRoot "env.ps1")

function Wake-Device {
    Write-Host "[Harness] Waking device & dismissing keyguard..."
    adb shell input keyevent 224 # KEYCODE_WAKEUP
    Start-Sleep -Milliseconds 400
    adb shell wm dismiss-keyguard
    adb shell input keyevent 82  # KEYCODE_MENU (unlock fallback)
}

function Launch-Game {
    Wake-Device
    Write-Host "[Harness] Launching Neon Touge..."
    adb shell monkey -p com.neontouge.rp4 -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 3
}

function Take-Screenshot {
    param([string]$OutFile)
    if (-not $OutFile) { $OutFile = "dist\device_screen.png" }
    $dir = Split-Path $OutFile -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    
    adb shell screencap -p /sdcard/sc.png
    adb pull /sdcard/sc.png $OutFile | Out-Null
    Write-Host "[Harness] Screenshot saved to: $OutFile"
}

function Send-Key {
    param([string]$Key)
    $code = switch ($Key.ToUpper()) {
        "A" { 96 }      # BUTTON_A
        "B" { 97 }      # BUTTON_B
        "X" { 99 }      # BUTTON_X
        "Y" { 100 }     # BUTTON_Y
        "ENTER" { 66 }  # KEYCODE_ENTER
        "BACK" { 4 }    # KEYCODE_BACK
        "UP" { 19 }     # KEYCODE_DPAD_UP
        "DOWN" { 20 }   # KEYCODE_DPAD_DOWN
        "LEFT" { 21 }   # KEYCODE_DPAD_LEFT
        "RIGHT" { 22 }  # KEYCODE_DPAD_RIGHT
        "SPACE" { 62 }  # KEYCODE_SPACE
        default { [int]$Key }
    }
    adb shell input keyevent $code
}

switch ($Action.ToLower()) {
    "wake" {
        Wake-Device
    }
    "launch" {
        Launch-Game
    }
    "screencap" {
        Take-Screenshot $Target
    }
    "key" {
        Send-Key $Target
    }
    "tap" {
        adb shell input tap $Target $Extra
    }
    "deploy" {
        $apk = Join-Path $global:NT_ROOT "dist\NeonTougeRP4.apk"
        if (-not (Test-Path $apk)) { throw "APK not found at $apk" }
        Write-Host "[Harness] Installing APK to RP4..."
        adb install -r $apk
    }
    "nav-hub" {
        Launch-Game
        Start-Sleep -Seconds 2
        Send-Key "ENTER"
        Start-Sleep -Seconds 2
        Send-Key "ENTER"
        Start-Sleep -Seconds 3
        if ($Target) { Take-Screenshot $Target }
    }
    "nav-freeroam" {
        Launch-Game
        Start-Sleep -Seconds 2
        Send-Key "ENTER"
        Start-Sleep -Seconds 2
        Send-Key "ENTER"
        Start-Sleep -Seconds 2
        Send-Key "ENTER"
        Start-Sleep -Seconds 5
        if ($Target) { Take-Screenshot $Target }
    }
    default {
        Write-Host "Usage: device_harness.ps1 [wake|launch|screencap|key|tap|deploy|nav-hub|nav-freeroam] [args]"
    }
}
