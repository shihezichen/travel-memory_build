<#
.SYNOPSIS
  Build a HarmonyOS HAP from a DevEco Studio project using the toolchain that
  ships inside the DevEco Studio install (Node + ohpm + hvigor + JBR).

.DESCRIPTION
  No separate Node / JDK / HarmonyOS SDK install is required: everything is
  taken from the DevEco Studio directory, so this works on a fresh machine that
  only has DevEco Studio installed.

  Output:
    <ProjectDir>\entry\build\default\outputs\default\entry-default-unsigned.hap

  IMPORTANT: the produced HAP is UNSIGNED. Installing on a commercial
  HarmonyOS device requires a signature (Huawei developer certificate + device
  UDID). Configure signingConfigs in <ProjectDir>\build-profile.json5, or build
  from the DevEco Studio GUI with "Automatically generate signature" enabled.

.PARAMETER ProjectDir
  Path to the HarmonyOS project root (the folder that contains build-profile.json5).

.PARAMETER DevEcoDir
  DevEco Studio install directory. Auto-detected when omitted.

.PARAMETER Task
  hvigor task to run. Default: assembleHap

.EXAMPLE
  .\build-hap.ps1 -ProjectDir D:\path\to\travel-memory_harmony
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [string]$DevEcoDir,
  [string]$Task = "assembleHap"
)
# NOTE: 'Continue' (not 'Stop') so benign stderr from native tools (hvigor WARN,
# node, java) does not abort the script. Real failures are caught via $LASTEXITCODE.
$ErrorActionPreference = 'Continue'

# --- Locate DevEco Studio ------------------------------------------------
if (-not $DevEcoDir) {
  $candidates = @(
    "D:\Program Files\Huawei\DevEco Studio",
    "C:\Program Files\Huawei\DevEco Studio",
    "${env:ProgramFiles}\Huawei\DevEco Studio",
    "${env:ProgramFiles(x86)}\Huawei\DevEco Studio"
  )
  $DevEcoDir = $candidates |
    Where-Object { Test-Path (Join-Path $_ "tools\hvigor\bin\hvigorw.bat") } |
    Select-Object -First 1
}
if (-not $DevEcoDir -or -not (Test-Path (Join-Path $DevEcoDir "tools\hvigor\bin\hvigorw.bat"))) {
  throw "DevEco Studio not found. Install it, or pass -DevEcoDir '<install path>'."
}
$DevEcoDir = (Resolve-Path $DevEcoDir).Path

# --- Toolchain environment (all bundled with DevEco Studio) -------------
$nodeDir = Join-Path $DevEcoDir "tools\node"
$sdkHome = Join-Path $DevEcoDir "sdk"      # parent of sdk\default (contains sdk-pkg.json)
$env:NODE_HOME          = $nodeDir
$env:DEVECO_SDK_HOME    = $sdkHome
$env:HARMONYOS_SDK_HOME = $sdkHome
$env:JAVA_HOME          = Join-Path $DevEcoDir "jbr"
$env:PATH = "$nodeDir;" +
            (Join-Path $DevEcoDir "tools\ohpm\bin") + ";" +
            (Join-Path $DevEcoDir "jbr\bin") + ";" +
            $env:PATH

# --- Build ---------------------------------------------------------------
$ProjectDir = (Resolve-Path $ProjectDir).Path
Set-Location $ProjectDir
Write-Host "==> DevEco Studio : $DevEcoDir"
Write-Host "==> node           : $(& node --version)"

Write-Host "==> ohpm install"
& (Join-Path $DevEcoDir "tools\ohpm\bin\ohpm.bat") install
if ($LASTEXITCODE -ne 0) { throw "ohpm install failed (exit=$LASTEXITCODE)" }

Write-Host "==> hvigorw $Task"
& (Join-Path $DevEcoDir "tools\hvigor\bin\hvigorw.bat") $Task
if ($LASTEXITCODE -ne 0) { throw "hvigorw $Task failed (exit=$LASTEXITCODE)" }

# --- Report artifact -----------------------------------------------------
$outDir = Join-Path $ProjectDir "entry\build\default\outputs\default"
$hap = Get-ChildItem $outDir -Filter "*.hap" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($hap) {
  Write-Host "==> HAP: $($hap.FullName)  ($([math]::Round($hap.Length / 1KB, 1)) KB)"
  if ($hap.Name -match 'unsigned') {
    Write-Warning "HAP is UNSIGNED. Real-device install needs signingConfigs in build-profile.json5 (Huawei developer cert)."
  }
} else {
  Write-Warning "No .hap found under $outDir"
}
