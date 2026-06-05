# Web-Installer fuer TokenWatch (vereinheitlichte Tauri-App)
#
# Einzeiler-Installation:
#   irm https://raw.githubusercontent.com/LSX-Apps/TokenWatch-Releases/main/install.ps1 | iex
#
# Laedt den neuesten Windows-Installer (.exe) herunter, entfernt das Internet-Flag
# (Mark of the Web / Smart App Control) und startet die Installation still.
$ErrorActionPreference = "Stop"

$ManifestUrl = "https://raw.githubusercontent.com/LSX-Apps/TokenWatch-Releases/main/tokenwatch-manifest.json?t=" + [Guid]::NewGuid().ToString("N")
Write-Host "Lade App-Informationen von GitHub..." -ForegroundColor Cyan

$response = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
$manifest = $response
if ($response -is [string]) {
    $cleanJson = $response.Trim().Trim([char]65279)
    $manifest = $cleanJson | ConvertFrom-Json
}
$latestVersion = $manifest.version
$downloadUrl   = $manifest.download_url
$expectedSha   = $manifest.sha256

if (-not $downloadUrl) { throw "Manifest enthaelt keine download_url." }

Write-Host "Neueste Version gefunden: v$latestVersion" -ForegroundColor Green
Write-Host "Lade Installationspaket herunter..." -ForegroundColor Cyan

$tempDir = Join-Path $env:TEMP ("TokenWatchInstall-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$setupPath = Join-Path $tempDir "TokenWatch-Setup.exe"

Invoke-WebRequest -Uri $downloadUrl -OutFile $setupPath -UseBasicParsing

Write-Host "Entsperre Installationspaket fuer Smart App Control..." -ForegroundColor Cyan
try { Unblock-File -LiteralPath $setupPath } catch {
    Write-Warning "Konnte Datei nicht entsperren (ggf. Admin-Rechte noetig)."
}

if ($expectedSha) {
    $actual = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expectedSha.ToLower()) {
        throw "SHA256 passt nicht (erwartet $expectedSha, bekommen $actual)."
    }
    Write-Host "SHA256 ok" -ForegroundColor DarkGray
}

Write-Host "Starte Installation..." -ForegroundColor Green
# Tauri/NSIS-Installer: /S = still installieren.
Start-Process -FilePath $setupPath -ArgumentList "/S" -Wait

Write-Host ""
Write-Host "Fertig. TokenWatch erscheint im Startmenue und im Infobereich (Tray)." -ForegroundColor Green
Write-Host "Beim ersten Start fuehrt dich die App durch die Einrichtung." -ForegroundColor Green
