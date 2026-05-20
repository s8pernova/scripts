# Restore-AntigravityIDE.ps1
# Copies old Antigravity user data into Antigravity IDE user data.
# - Stops Antigravity first
# - Makes a timestamped backup before copying
# - Copies only user data

$ErrorActionPreference = "Stop"

Write-Host "Closing Antigravity processes..."

taskkill /F /IM "Antigravity IDE.exe" 2>$null
taskkill /F /IM "Antigravity.exe" 2>$null

$oldRoaming = "$env:APPDATA\Antigravity"
$newRoaming = "$env:APPDATA\Antigravity IDE"

$oldExtensions = "$env:USERPROFILE\.antigravity\extensions"
$newExtensions = "$env:USERPROFILE\.antigravity-ide\extensions"

$oldGemini = "$env:USERPROFILE\.gemini\antigravity"
$newGemini = "$env:USERPROFILE\.gemini\antigravity-ide"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$env:USERPROFILE\Desktop\antigravity-restore-backup-$stamp"

Write-Host "Making backup at:"
Write-Host $backup

New-Item -ItemType Directory -Path $backup -Force | Out-Null

$itemsToBackUp = @(
    "$env:APPDATA\Antigravity",
    "$env:APPDATA\Antigravity IDE",
    "$env:USERPROFILE\.antigravity",
    "$env:USERPROFILE\.antigravity-ide",
    "$env:USERPROFILE\.gemini\antigravity",
    "$env:USERPROFILE\.gemini\antigravity-ide",
    "$env:USERPROFILE\.gemini\antigravity-backup"
)

foreach ($item in $itemsToBackUp) {
    if (Test-Path $item) {
        Copy-Item $item $backup -Recurse -Force
    }
}

Write-Host "Backup complete."

if ((Test-Path "$oldRoaming\User") -and (Test-Path "$newRoaming\User")) {
    Write-Host "Copying old editor user data into Antigravity IDE..."
    Copy-Item "$oldRoaming\User\*" "$newRoaming\User\" -Recurse -Force
} else {
    Write-Host "Skipping editor user data. Source or destination User folder missing."
}

if (Test-Path $oldExtensions) {
    Write-Host "Copying old extensions into Antigravity IDE extension folder..."
    New-Item -ItemType Directory $newExtensions -Force | Out-Null
    Copy-Item "$oldExtensions\*" "$newExtensions\" -Recurse -Force
} else {
    Write-Host "Skipping extensions. Old extension folder missing."
}

if (Test-Path $oldGemini) {
    Write-Host "Copying old Gemini/Antigravity agent data into Antigravity IDE folder..."
    New-Item -ItemType Directory $newGemini -Force | Out-Null
    Copy-Item "$oldGemini\*" "$newGemini\" -Recurse -Force
} else {
    Write-Host "Skipping Gemini/agent data. Old Gemini folder missing."
}

Write-Host ""
Write-Host "Done."
Write-Host "Backup saved here:"
Write-Host $backup