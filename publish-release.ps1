<#
.SYNOPSIS
  Publish a built HAP and/or APK as a GitHub Release of travel-memory_build.

.DESCRIPTION
  Creates a GitHub release (default tag vYYYY.MM.dd) and uploads the given
  artifact(s) as release assets. This is the one-click "publish new package" step.

  Auth: uses `git credential fill` for github.com, or the GITHUB_TOKEN / GH_TOKEN
  environment variable (checked first). No secrets are hard-coded.

  Tag convention (date-based): vYYYY.MM.dd  (e.g. v2026.10.18)
    - If the tag already exists (multiple builds in one day), -2, -3 ... is appended.
    - Day-to-day builds use the date tag.

  The script is ASCII-only; any non-ASCII passed via -Name/-Body is JSON-escaped
  to \uXXXX so it survives PowerShell 5.1 + git without mangling.

.PARAMETER HapPath  Path to the .hap to publish (optional).
.PARAMETER ApkPath  Path to the .apk to publish (optional).
.PARAMETER Tag      Release tag. Default: v<yyyy.MM.dd>.
.PARAMETER Name     Release title.
.PARAMETER Body     Release notes.
.PARAMETER Repo     owner/repo. Default: shihezichen/travel-memory_build

.EXAMPLE
  .\publish-release.ps1 -HapPath D:\out\entry-default-signed.hap -ApkPath D:\out\app-debug.apk
.EXAMPLE
  .\publish-release.ps1 -ApkPath D:\out\app-debug.apk -Tag v2026.10.18 -Name "Travel Memory 2026-10-18"
  (Non-ASCII names/notes are auto-escaped; a Chinese title also works.)
#>
[CmdletBinding()]
param(
  [string]$HapPath,
  [string]$ApkPath,
  [string]$Tag,
  [string]$Name,
  [string]$Body,
  [string]$Repo = "shihezichen/travel-memory_build"
)
# 'Continue' so benign native stderr (git, etc.) does not abort the script.
$ErrorActionPreference = 'Continue'

# --- defaults ---
if (-not $Tag)  { $Tag  = "v" + (Get-Date -Format "yyyy.MM.dd") }
if (-not $Name) { $Name = "Travel Memory build $Tag" }
if (-not $Body) {
  $Body = "Automated build $Tag.`n`nAssets:`n" +
          $(if ($HapPath) { "- HarmonyOS HAP (signed)`n" } else { "" }) +
          $(if ($ApkPath)  { "- Android APK (debug)`n" }    else { "" }) +
          "`nBuilt with the travel-memory_build scripts."
}

# --- JSON string escaper: keeps the payload pure ASCII (non-ASCII -> \uXXXX) ---
function ConvertTo-JsonString([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $code = [int][char]$ch
    if     ($ch -eq '"')  { [void]$sb.Append('\"') }
    elseif ($ch -eq '\')  { [void]$sb.Append('\\') }
    elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
    elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
    elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
    elseif ($code -ge 32 -and $code -lt 127) { [void]$sb.Append($ch) }
    else   { [void]$sb.Append(('\u{0:x4}' -f $code)) }
  }
  return $sb.ToString()
}

# --- resolve auth token ---
$token = $env:GITHUB_TOKEN
if (-not $token) { $token = $env:GH_TOKEN }
if (-not $token) {
  $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>&1
  $token = ($cred | Where-Object { $_ -like 'password=*' }) -replace 'password=', ''
}
if (-not $token) {
  throw "No GitHub token found. Set GITHUB_TOKEN, or configure git credentials for github.com."
}
$headers = @{ Authorization = "token $token"; Accept = "application/vnd.github+json"; "User-Agent" = "travel-memory-build" }

# --- validate assets ---
$assets = @()
if ($HapPath) {
  if (Test-Path $HapPath) { $assets += @{ path = (Resolve-Path $HapPath).Path; name = Split-Path $HapPath -Leaf; ct = "application/octet-stream" } }
  else { throw "HAP not found: $HapPath" }
}
if ($ApkPath) {
  if (Test-Path $ApkPath) { $assets += @{ path = (Resolve-Path $ApkPath).Path; name = Split-Path $ApkPath -Leaf; ct = "application/vnd.android.package-archive" } }
  else { throw "APK not found: $ApkPath" }
}
if ($assets.Count -eq 0) { throw "Nothing to publish. Pass -HapPath and/or -ApkPath." }

# --- create release (bump tag with -2,-3... if it already exists) ---
$created = $null; $usedTag = $Tag
for ($i = 1; $i -le 5 -and -not $created; $i++) {
  $tryTag = if ($i -eq 1) { $Tag } else { "$Tag-$i" }
  $usedTag = $tryTag
  $payload = '{"tag_name":"' + (ConvertTo-JsonString $tryTag) + '","name":"' + (ConvertTo-JsonString $Name) + '","body":"' + (ConvertTo-JsonString $Body) + '","target_commitish":"main"}'
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
  try {
    $created = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Method Post -Headers $headers -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 60
  } catch {
    if ($_.Exception.Message -match 'already_exists') { Write-Host "tag $tryTag already exists, trying next..."; continue }
    Write-Host "release create error: $($_.Exception.Message)"
    if ($_.Exception.Response) { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd() }
    exit 1
  }
}
if (-not $created) { throw "Could not create a release for tag base '$Tag'." }
Write-Host "RELEASE: $($created.tag_name)  ->  $($created.html_url)"

# --- upload assets ---
$upload = $created.upload_url -replace '\{\?name,label\}', ''
foreach ($a in $assets) {
  $u = "$upload`?name=$($a.name)"
  try {
    $r = Invoke-RestMethod -Uri $u -Method Post -Headers $headers -InFile $a.path -ContentType $a.ct -TimeoutSec 300
    Write-Host "UPLOADED: $($a.name)  ($([math]::Round($r.size / 1KB, 1))KB)  ->  $($r.browser_download_url)"
  } catch {
    Write-Host "upload error ($($a.name)): $($_.Exception.Message)"
  }
}
