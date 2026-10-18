<#
.SYNOPSIS
  Bootstrap a local Android build toolchain on Windows:
    JDK 17 + Gradle + Android SDK (cmdline-tools, platform-tools, platforms, build-tools).

.DESCRIPTION
  Everything is installed under <ToolsDir>:
    <ToolsDir>\jdk17\...            JDK 17 (Temurin/Adoptium, Azul fallback)
    <ToolsDir>\gradle-<ver>\        Gradle
    <ToolsDir>\sdk\                 Android SDK
    <ToolsDir>\cmdline-tools\       Android sdkmanager

  Downloads are resumable (HTTP Range + 206 handling) so a slow or flaky
  network will not corrupt a partial file. Run this once, then use build-apk.ps1.

  NOTE: sdkmanager needs a JVM on PATH. If no system `java` exists, the script
  points java at DevEco Studio's bundled JBR (if present) just for setup.

.PARAMETER ToolsDir        Install dir. Default: <this script>\..\.tools
.PARAMETER GradleVersion   Default: 8.9
.PARAMETER CompileSdk      Default: 35
.PARAMETER BuildTools      Default: 35.0.0

.EXAMPLE
  .\bootstrap-android-toolchain.ps1
  .\bootstrap-android-toolchain.ps1 -ToolsDir D:\android-tools -GradleVersion 8.9
#>
[CmdletBinding()]
param(
  [string]$ToolsDir = (Join-Path (Split-Path $PSScriptRoot -Parent) ".tools"),
  [string]$GradleVersion = "8.9",
  [string]$CompileSdk = "35",
  [string]$BuildTools = "35.0.0"
)
# NOTE: 'Continue' (not 'Stop') so benign stderr from native tools (sdkmanager,
# java) does not abort the script. Failures are caught via explicit checks / throw.
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

# --- Resumable downloader ------------------------------------------------
function Get-Resumable {
  param([string]$Url, [string]$OutFile)
  $total = 0
  try {
    $h = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 60
    $total = [int64]$h.Headers['Content-Length']
  } catch { $total = 0 }

  $existing = 0
  if (Test-Path $OutFile) { $existing = (Get-Item $OutFile).Length }
  if ($total -gt 0 -and $existing -ge $total) { Write-Host "  already complete: $OutFile"; return }

  $fs = [System.IO.File]::Open($OutFile, 'OpenOrCreate', 'Write')
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Timeout = 180000
    if ($existing -gt 0) { $req.AddRange($existing) }
    $resp = $req.GetResponse()
    # If the server ignored Range (200 instead of 206), start over.
    if ($existing -gt 0 -and [int]$resp.StatusCode -ne 206) {
      $existing = 0; $fs.Seek(0, 'Begin') | Out-Null; $fs.SetLength(0) | Out-Null
    } else {
      $fs.Seek($existing, 'Begin') | Out-Null
    }
    $rs = $resp.GetResponseStream()
    $buffer = New-Object byte[] 65536
    while (($read = $rs.Read($buffer, 0, $buffer.Length)) -gt 0) { $fs.Write($buffer, 0, $read) }
    $rs.Close(); $resp.Close()
  } finally { $fs.Close() }

  if ($total -gt 0 -and (Get-Item $OutFile).Length -lt $total) {
    throw "download incomplete: $OutFile ($((Get-Item $OutFile).Length)/$total bytes) - re-run to resume"
  }
}

# --- Make sure a JVM is available for sdkmanager -------------------------
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
  foreach ($jbr in @("D:\Program Files\Huawei\DevEco Studio\jbr\bin",
                      "C:\Program Files\Huawei\DevEco Studio\jbr\bin")) {
    if (Test-Path (Join-Path $jbr "java.exe")) { $env:PATH = "$jbr;" + $env:PATH; break }
  }
}

# --- 1) Android cmdline-tools + SDK packages -----------------------------
$ct = Join-Path $ToolsDir "cmdline-tools"
if (-not (Test-Path (Join-Path $ct "latest\bin\sdkmanager.bat"))) {
  Write-Host "==> Android command-line tools"
  Get-Resumable "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" (Join-Path $ToolsDir "cmdtools.zip")
  Expand-Archive (Join-Path $ToolsDir "cmdtools.zip") -DestinationPath (Join-Path $ct "tmp") -Force
  Move-Item (Join-Path $ct "tmp\cmdline-tools") (Join-Path $ct "latest") -Force
  Remove-Item (Join-Path $ToolsDir "cmdtools.zip") -Force
}
$env:ANDROID_HOME = Join-Path $ToolsDir "sdk"
$sdkmanager = Join-Path $ct "latest\bin\sdkmanager.bat"
Write-Host "==> SDK packages: platform-tools, platforms;android-$CompileSdk, build-tools;$BuildTools"
& $sdkmanager --sdk_root="$env:ANDROID_HOME" "platform-tools" "platforms;android-$CompileSdk" "build-tools;$BuildTools"
if ($LASTEXITCODE -ne 0) { throw "sdkmanager package install failed" }
Write-Host "==> Accepting licenses"
("y`n" * 30) | & $sdkmanager --sdk_root="$env:ANDROID_HOME" --licenses | Out-Null

# --- 2) JDK 17 (Adoptium API first, Azul CDN fallback) -------------------
$jdkDir = Join-Path $ToolsDir "jdk17"
if (-not (Test-Path (Join-Path $jdkDir "bin\java.exe"))) {
  Write-Host "==> JDK 17"
  $zip = Join-Path $ToolsDir "jdk17.zip"
  $urls = @(
    "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/zip",
    "https://cdn.azul.com/zulu/bin/zulu17.46.19-ca-jdk17.0.13-win_x64.zip"
  )
  $ok = $false
  foreach ($u in $urls) {
    try { Get-Resumable $u $zip; $ok = $true; break }
    catch { Write-Warning "JDK source failed ($u): $($_.Exception.Message)" }
  }
  if (-not $ok) { throw "Could not download JDK 17 from any source" }
  Expand-Archive $zip -DestinationPath (Join-Path $ToolsDir "jdk17-tmp") -Force
  $sub = Get-ChildItem (Join-Path $ToolsDir "jdk17-tmp") -Directory | Select-Object -First 1
  if (Test-Path $jdkDir) { Remove-Item $jdkDir -Recurse -Force }
  Move-Item $sub.FullName $jdkDir -Force
  Remove-Item (Join-Path $ToolsDir "jdk17-tmp") -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
}

# --- 3) Gradle -----------------------------------------------------------
$gradleDir = Join-Path $ToolsDir "gradle-$GradleVersion"
if (-not (Test-Path (Join-Path $gradleDir "bin\gradle.bat"))) {
  Write-Host "==> Gradle $GradleVersion"
  $gz = Join-Path $ToolsDir "gradle.zip"
  Get-Resumable "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip" $gz
  Expand-Archive $gz -DestinationPath $ToolsDir -Force
  Remove-Item $gz -Force
}

Write-Host "==> Toolchain ready under $ToolsDir"
Write-Host "    Next: .\build-apk.ps1 -ProjectDir <android repo>"
