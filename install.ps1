# Aegis one-command installer for Windows.
#
# Downloads the latest release, unpacks it into %USERPROFILE%\Aegis, and
# launches it. Nothing is installed system-wide and no admin rights are
# required.
#
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/voyb/aegis-vault/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$repo = "voyb/aegis-vault"
$dest = "$HOME\Aegis"
$url  = "https://github.com/$repo/releases/latest/download/Aegis-windows.zip"

Write-Host "Installing Aegis to $dest ..."
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$tmpZip = Join-Path $env:TEMP "aegis-install.zip"
Invoke-WebRequest -Uri $url -OutFile $tmpZip

Expand-Archive -Path $tmpZip -DestinationPath $dest -Force
Remove-Item $tmpZip -Force

Write-Host "Installed. Launching Aegis..."
Start-Process "$dest\Aegis.exe"

Write-Host ""
Write-Host "Aegis lives in $dest - keep that folder together (the executable"
Write-Host "needs index.html and vendor\ next to it). Run it again any time with:"
Write-Host "  $dest\Aegis.exe"
