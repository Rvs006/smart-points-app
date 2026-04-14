param(
  [int]$Port = 8000,
  [string]$File = "Electracom_Smart_Point_Reference_v18.html",
  [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
function Get-FreePort {
  param([int]$StartPort)

  for ($candidate = $StartPort; $candidate -lt ($StartPort + 50); $candidate++) {
    $listener = Get-NetTCPConnection -LocalPort $candidate -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) {
      return $candidate
    }
  }

  throw "Could not find a free port starting at $StartPort."
}

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
  $Port = Get-FreePort ($Port + 1)
}

$url = "http://localhost:$Port/$File"

Start-Process -FilePath "python" `
  -ArgumentList "-m http.server $Port" `
  -WorkingDirectory $root `
  -WindowStyle Minimized
Start-Sleep -Seconds 2

if ($NoOpen) {
  Write-Host "Preview server started."
}

if (-not $NoOpen) {
  Start-Process $url
}

Write-Host "App URL: $url"
