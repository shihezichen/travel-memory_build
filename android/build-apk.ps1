<#
.SYNOPSIS
  Build an Android APK from a Gradle project using a locally-bootstrapped toolchain.

.DESCRIPTION
  Expects the toolchain produced by bootstrap-android-toolchain.ps1:
    <ToolsDir>\jdk17\...\bin\java.exe   (JDK 17)
    <ToolsDir>\gradle-<ver>\bin\gradle.bat
    <ToolsDir>\sdk\                     (Android SDK)

  The script writes <ProjectDir>\local.properties (sdk.dir=...) and runs
  `gradle assemble<Variant>`.

  NOTE: the "debug" variant is auto-signed by Android (installable on any dev
  device / with "unknown sources" enabled). The "release" variant requires a
  signing keystore referenced by app/build.gradle(.kts).

.PARAMETER ProjectDir
  Path to the Android Gradle project root (contains settings.gradle).

.PARAMETER ToolsDir
  Toolchain directory. Default: <this script>\..\.tools

.PARAMETER Variant
  debug (default) or release.

.EXAMPLE
  .\build-apk.ps1 -ProjectDir D:\path\to\travel-memory_android
  .\build-apk.ps1 -ProjectDir D:\path\to\travel-memory_android -Variant release
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [string]$ToolsDir = (Join-Path (Split-Path $PSScriptRoot -Parent) ".tools"),
  [ValidateSet("debug", "release")][string]$Variant = "debug"
)
# NOTE: 'Continue' (not 'Stop') so benign stderr from native tools (java -version,
# gradle progress/warnings) does not abort the script. Failures caught via $LASTEXITCODE.
$ErrorActionPreference = 'Continue'

# --- Locate JDK home (unzipped top folder name is version-specific) ------
$jdkHome = Get-ChildItem $ToolsDir -Directory -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $jdkHome) { throw "JDK not found under '$ToolsDir'. Run bootstrap-android-toolchain.ps1 first." }

# --- Locate Gradle -------------------------------------------------------
$gradleDir = Get-ChildItem $ToolsDir -Directory -Filter "gradle-*" -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName "bin\gradle.bat") } |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $gradleDir) { throw "Gradle not found under '$ToolsDir'. Run bootstrap-android-toolchain.ps1 first." }

# --- Environment ---------------------------------------------------------
$env:JAVA_HOME    = $jdkHome
$env:ANDROID_HOME = Join-Path $ToolsDir "sdk"
$env:PATH = "$jdkHome\bin;$gradleDir\bin;" + $env:PATH
Write-Host "==> JAVA_HOME=$jdkHome"
& (Join-Path $jdkHome "bin\java.exe") -version

# --- local.properties ----------------------------------------------------
$ProjectDir = (Resolve-Path $ProjectDir).Path
$sdkDir = ($env:ANDROID_HOME -replace '\\', '/')
Set-Content -Path (Join-Path $ProjectDir "local.properties") -Value "sdk.dir=$sdkDir"

# --- Build ---------------------------------------------------------------
Set-Location $ProjectDir
$cap = $Variant.Substring(0, 1).ToUpper() + $Variant.Substring(1)
$task = "assemble$cap"
Write-Host "==> gradle $task"
& (Join-Path $gradleDir "bin\gradle.bat") $task --no-daemon --stacktrace
if ($LASTEXITCODE -ne 0) { throw "gradle $task failed (exit=$LASTEXITCODE)" }

# --- Report artifact -----------------------------------------------------
$apk = Get-ChildItem (Join-Path $ProjectDir "app\build\outputs\apk\$Variant") -Filter "*.apk" -ErrorAction SilentlyContinue |
       Select-Object -First 1
if ($apk) { Write-Host "==> APK: $($apk.FullName)  ($([math]::Round($apk.Length / 1KB, 1)) KB)" }
else { throw "APK not found for variant '$Variant'" }
