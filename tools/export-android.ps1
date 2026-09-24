# Builds everything and exports the signed APK to dist/NeonTougeRP4.apk.
#   -SkipNative   reuse existing native libraries
#   -Debug        debug export (debug keystore, debug .so)
param([switch]$SkipNative, [switch]$Debug)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "env.ps1")
$godotDir = Join-Path $NT_ROOT "godot"
$dist = Join-Path $NT_ROOT "dist"
New-Item -ItemType Directory -Force $dist | Out-Null

# 1. Native extension (arm64).
if (-not $SkipNative) {
    & (Join-Path $PSScriptRoot "build-native.ps1") -Platform android -Target $(if ($Debug) { "template_debug" } else { "template_release" })
}

# 2. RP4Bridge Android plugin (AAR) -> addon folder.
$env:GRADLE_USER_HOME = "$NT_TOOLCHAIN\gradle-home"
Push-Location (Join-Path $NT_ROOT "android_plugin")
& .\gradlew.bat --no-daemon -q :rp4bridge:assembleRelease
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "plugin build failed" }
Pop-Location
$aarDir = Join-Path $godotDir "addons\rp4_bridge\bin"
New-Item -ItemType Directory -Force $aarDir | Out-Null
Copy-Item (Join-Path $NT_ROOT "android_plugin\rp4bridge\build\outputs\aar\rp4bridge-release.aar") $aarDir -Force

# 3. Android build template (equivalent of "Project > Install Android Build Template").
$buildDir = Join-Path $godotDir "android\build"
$version = (Get-Content "$NT_TOOLCHAIN\godot\editor_data\export_templates\4.7.2.stable\version.txt").Trim()
$versionFile = Join-Path $godotDir "android\.build_version"
if (-not (Test-Path $versionFile) -or (Get-Content $versionFile).Trim() -ne $version) {
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
    New-Item -ItemType Directory -Force $buildDir | Out-Null
    & tar.exe -xf "$NT_TOOLCHAIN\godot\editor_data\export_templates\4.7.2.stable\android_source.zip" -C $buildDir
    Set-Content -Path $versionFile -Value $version -Encoding ascii -NoNewline
    New-Item -ItemType File -Force (Join-Path $buildDir ".gdignore") | Out-Null
}

# 4. Release keystore (generated once; BACK IT UP - updates must be signed with the same key).
$ksDir = Join-Path $NT_ROOT "keystore"
$ks = Join-Path $ksDir "neontouge.jks"
$props = Join-Path $ksDir "keystore.properties"
if (-not (Test-Path $ks)) {
    New-Item -ItemType Directory -Force $ksDir | Out-Null
    $pw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    & "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -v -keystore $ks -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 36500 `
        -alias neontouge -storepass $pw -keypass $pw -dname "CN=Neon Touge RP4, O=Neon Touge, C=JP" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "keytool failed" }
    "alias=neontouge`npassword=$pw" | Set-Content -Encoding ascii $props
}
$kv = @{}
Get-Content $props | ForEach-Object { $p = $_ -split "=", 2; $kv[$p[0]] = $p[1] }
if ($Debug) {
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $ks
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = $kv.alias
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = $kv.password
} else {
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $ks
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $kv.alias
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $kv.password
}

# 5. Import + export.
Push-Location $godotDir
& $NT_GODOT --headless --path . --import | Out-Null
$apk = Join-Path $dist $(if ($Debug) { "NeonTougeRP4-debug.apk" } else { "NeonTougeRP4.apk" })
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
& $NT_GODOT --headless --path . $mode "Android RP4" $apk
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0 -or -not (Test-Path $apk)) { throw "export failed ($code)" }

# 6. Verify.
$bt = "$env:ANDROID_HOME\build-tools\36.1.0"
$java = if ($env:JAVA_HOME) { "$env:JAVA_HOME\bin\java.exe" } else { "java.exe" }
& $java -jar "$bt\lib\apksigner.jar" verify --print-certs $apk
& "$bt\aapt.exe" dump badging $apk | Select-String -Pattern "package:|sdkVersion|targetSdkVersion|uses-permission|native-code|application-label"
"APK: $apk  ($([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB)"
