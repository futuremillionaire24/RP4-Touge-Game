# Session environment for the portable toolchain. Dot-source: . tools\env.ps1
$global:NT_TOOLCHAIN = "D:\RP4Toolchain"
$env:JAVA_HOME = "$NT_TOOLCHAIN\jdk17"
$env:ANDROID_HOME = "$NT_TOOLCHAIN\android-sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_NDK_ROOT = "$env:ANDROID_HOME\ndk\28.1.13356709"
$env:PATH = "$NT_TOOLCHAIN\python;$NT_TOOLCHAIN\python\Scripts;$NT_TOOLCHAIN\llvm-mingw\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
$global:NT_GODOT = "$NT_TOOLCHAIN\godot\godot_console.exe"
$global:NT_ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
