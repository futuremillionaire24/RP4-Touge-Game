# Neon Touge RP4 - portable toolchain installer (idempotent, no admin, no global PATH changes).
# Everything lands in $Root (default D:\RP4Toolchain). Re-run safely; finished steps are skipped.
param(
    [string]$Root = "D:\RP4Toolchain",
    [string]$GodotVersion = "4.7.2",
    [string]$NdkVersion = "28.1.13356709",
    # 20.0+ replaced the Java sdkmanager with a native android.exe wrapper that crashes (0xC0000409)
    # on Windows 10 19045; 19.0 is the last classic release.
    [string]$CmdlineTools = "cmdline-tools;19.0",
    [string[]]$SdkPlatforms = @("platforms;android-34", "platforms;android-35", "platforms;android-36"),
    [string[]]$BuildTools = @("build-tools;34.0.0", "build-tools;35.0.1", "build-tools;36.0.0", "build-tools;36.1.0"),
    # The Godot 4.7 Gradle template strips native libraries with this NDK.
    [string]$TemplateNdkVersion = "29.0.14206865"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Downloads = Join-Path $Root "_downloads"
New-Item -ItemType Directory -Force -Path $Root, $Downloads | Out-Null

function Get-File([string]$Url, [string]$Name) {
    $dest = Join-Path $Downloads $Name
    if (-not (Test-Path "$dest.ok")) {
        Write-Host "  downloading $Name"
        & curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o $dest $Url
        if ($LASTEXITCODE -ne 0) { throw "download failed: $Url" }
        New-Item -ItemType File -Path "$dest.ok" | Out-Null
    }
    return $dest
}

function Expand-Into([string]$Archive, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    & tar.exe -xf $Archive -C $Dest
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $Archive" }
}

function Step([string]$Name, [string]$Marker, [scriptblock]$Body) {
    if (Test-Path $Marker) { Write-Host "[skip] $Name"; return }
    Write-Host "[run ] $Name"
    & $Body
    Set-Content -Path $Marker -Value (Get-Date -Format o) -Encoding ascii
}

# ---- JDK 17 (Temurin) --------------------------------------------------------------------------
$JdkDir = Join-Path $Root "jdk17"
Step "JDK 17" (Join-Path $Root ".jdk.done") {
    $asset = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"
    $zip = Get-File $asset[0].binary.package.link "jdk17.zip"
    $tmp = Join-Path $Root "_jdk_tmp"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Into $zip $tmp
    if (Test-Path $JdkDir) { Remove-Item -Recurse -Force $JdkDir }
    Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName $JdkDir
    Remove-Item -Recurse -Force $tmp
}
$env:JAVA_HOME = $JdkDir

# ---- Android SDK + NDK -------------------------------------------------------------------------
$SdkDir = Join-Path $Root "android-sdk"
Step "Android $CmdlineTools" (Join-Path $Root ".cmdline.$($CmdlineTools -replace '[;:]', '_').done") {
    $repo = [xml](Invoke-WebRequest -UseBasicParsing "https://dl.google.com/android/repository/repository2-3.xml").Content
    $pkg = $repo.SelectSingleNode("//remotePackage[@path='$CmdlineTools']")
    $file = ($pkg.archives.archive | Where-Object { $_.'host-os' -eq 'windows' }).complete.url
    $zip = Get-File "https://dl.google.com/android/repository/$file" $file
    $tmp = Join-Path $Root "_clt_tmp"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Into $zip $tmp
    $latest = Join-Path $SdkDir "cmdline-tools\latest"
    New-Item -ItemType Directory -Force -Path (Split-Path $latest) | Out-Null
    if (Test-Path $latest) { Remove-Item -Recurse -Force $latest }
    Move-Item (Join-Path $tmp "cmdline-tools") $latest
    Remove-Item -Recurse -Force $tmp
}
$env:ANDROID_HOME = $SdkDir
$env:ANDROID_SDK_ROOT = $SdkDir
$SdkManager = Join-Path $SdkDir "cmdline-tools\latest\bin\sdkmanager.bat"

Step "Android SDK licenses" (Join-Path $Root ".licenses.done") {
    $yes = ("y`n" * 40)
    $yes | & $SdkManager --sdk_root=$SdkDir --licenses | Out-Null
}

$packages = @("platform-tools") + $SdkPlatforms + $BuildTools + @("ndk;$NdkVersion", "ndk;$TemplateNdkVersion")
$pkgKey = ($packages -join "|").GetHashCode()
Step "Android SDK packages ($($packages -join ', '))" (Join-Path $Root ".sdkpkgs.$pkgKey.done") {
    # cmd.exe treats ';' as an argument separator, so every package id must be quoted for the .bat.
    $quoted = $packages | ForEach-Object { "`"$_`"" }
    & $SdkManager --sdk_root=$SdkDir --install @quoted
    if ($LASTEXITCODE -ne 0) { throw "sdkmanager install failed" }
}

# ---- Godot editor (self-contained) + Android export templates ----------------------------------
$GodotDir = Join-Path $Root "godot"
$GodotTag = "$GodotVersion-stable"
Step "Godot $GodotVersion editor" (Join-Path $Root ".godot.$GodotVersion.done") {
    $zip = Get-File "https://github.com/godotengine/godot/releases/download/$GodotTag/Godot_v$($GodotTag)_win64.exe.zip" "godot-$GodotVersion.zip"
    New-Item -ItemType Directory -Force -Path $GodotDir | Out-Null
    Expand-Into $zip $GodotDir
    Get-ChildItem $GodotDir -Filter "Godot_v*_win64.exe" | Where-Object { $_.Name -notmatch "console" } | ForEach-Object { Copy-Item $_.FullName (Join-Path $GodotDir "godot.exe") -Force }
    Get-ChildItem $GodotDir -Filter "Godot_v*_win64_console.exe" | ForEach-Object { Copy-Item $_.FullName (Join-Path $GodotDir "godot_console.exe") -Force }
    # Self-contained mode: editor settings, caches and export templates live next to the binary.
    New-Item -ItemType File -Force -Path (Join-Path $GodotDir "._sc_") | Out-Null
}

$TplDir = Join-Path $GodotDir ("editor_data\export_templates\" + $GodotVersion + ".stable")
Step "Godot Android export templates" (Join-Path $Root ".templates.$GodotVersion.done") {
    $tpz = Get-File "https://github.com/godotengine/godot/releases/download/$GodotTag/Godot_v$($GodotTag)_export_templates.tpz" "templates-$GodotVersion.tpz"
    $tmp = Join-Path $Root "_tpl_tmp"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp, $TplDir | Out-Null
    $entries = & tar.exe -tf $tpz | Where-Object { $_ -match '^templates/(android_|version\.txt)' }
    & tar.exe -xf $tpz -C $tmp @entries
    if ($LASTEXITCODE -ne 0) { throw "template extract failed" }
    Copy-Item (Join-Path $tmp "templates\*") $TplDir -Recurse -Force
    Remove-Item -Recurse -Force $tmp
}

# ---- Python (portable, NuGet package) + SCons --------------------------------------------------
$PyDir = Join-Path $Root "python"
Step "Python + SCons" (Join-Path $Root ".python.done") {
    $idx = Invoke-RestMethod "https://api.nuget.org/v3-flatcontainer/python/index.json"
    $ver = ($idx.versions | Where-Object { $_ -match '^3\.13\.\d+$' } | Select-Object -Last 1)
    $nupkg = Get-File "https://api.nuget.org/v3-flatcontainer/python/$ver/python.$ver.nupkg" "python-$ver.zip"
    $tmp = Join-Path $Root "_py_tmp"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Into $nupkg $tmp
    if (Test-Path $PyDir) { Remove-Item -Recurse -Force $PyDir }
    Move-Item (Join-Path $tmp "tools") $PyDir
    Remove-Item -Recurse -Force $tmp
    & (Join-Path $PyDir "python.exe") -m pip install --disable-pip-version-check --quiet scons
    if ($LASTEXITCODE -ne 0) { throw "pip install scons failed" }
}

# ---- llvm-mingw (Windows desktop build of the GDExtension, no MSVC needed) ---------------------
$MingwDir = Join-Path $Root "llvm-mingw"
Step "llvm-mingw" (Join-Path $Root ".mingw.done") {
    $rel = Invoke-RestMethod "https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -match 'ucrt-x86_64\.zip$' } | Select-Object -First 1
    $zip = Get-File $asset.browser_download_url "llvm-mingw.zip"
    $tmp = Join-Path $Root "_mingw_tmp"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Into $zip $tmp
    if (Test-Path $MingwDir) { Remove-Item -Recurse -Force $MingwDir }
    Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName $MingwDir
    Remove-Item -Recurse -Force $tmp
}

# ---- Godot editor settings: point Android export at this toolchain -----------------------------
Step "Godot editor settings" (Join-Path $Root ".godot-settings.$GodotVersion.done") {
    $major = ($GodotVersion -split '\.')[0..1] -join '.'
    $settings = Join-Path $GodotDir "editor_data\editor_settings-$major.tres"
    $sdk = $SdkDir -replace '\\', '/'
    $jdk = $JdkDir -replace '\\', '/'
    if (-not (Test-Path $settings)) {
        & (Join-Path $GodotDir "godot_console.exe") --headless --quit | Out-Null
    }
    $text = if (Test-Path $settings) { Get-Content $settings -Raw } else { "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n" }
    $text = [regex]::Replace($text, '(?m)^export/android/(android_sdk_path|java_sdk_path) = .*\r?\n', '')
    $text = $text.TrimEnd() + "`nexport/android/android_sdk_path = `"$sdk`"`nexport/android/java_sdk_path = `"$jdk`"`n"
    [IO.File]::WriteAllText($settings, $text)
}

Write-Host ""
Write-Host "Toolchain ready in $Root"
Write-Host "  JDK      $JdkDir"
Write-Host "  SDK      $SdkDir (NDK $NdkVersion)"
Write-Host "  Godot    $GodotDir\godot_console.exe ($GodotVersion, self-contained)"
Write-Host "  Python   $PyDir\python.exe (+ SCons)"
Write-Host "  MinGW    $MingwDir"
