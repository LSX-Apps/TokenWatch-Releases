# Web-Installer fuer Claude Usage Tray
$ErrorActionPreference = "Stop"

$ManifestUrl = "https://raw.githubusercontent.com/LSX-Apps/CC-Nutzung-Releases/main/ccusage-manifest.json"
Write-Host "Lade App-Informationen von GitHub..." -ForegroundColor Cyan

$manifest = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
$latestVersion = $manifest.version
$downloadUrl = $manifest.download_url

Write-Host "Neueste Version gefunden: v$latestVersion" -ForegroundColor Green
Write-Host "Lade Installationspaket herunter..." -ForegroundColor Cyan

$tempDir = Join-Path $env:TEMP ("ClaudeUsageTrayInstall-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$zipPath = Join-Path $tempDir "update.zip"
Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

Write-Host "Entsperre Installationspaket fuer Smart App Control..." -ForegroundColor Cyan
try {
    Unblock-File -LiteralPath $zipPath
} catch {
    Write-Warning "Konnte Datei nicht entsperren. Moeglicherweise sind Admin-Rechte erforderlich oder Smart App Control blockiert den Vorgang."
}

$extractDir = Join-Path $tempDir "extract"
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

Write-Host "Entpacke Dateien..." -ForegroundColor Cyan
Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

$source = $extractDir
if (!(Test-Path -LiteralPath (Join-Path $source "ccusage-setup-wizard.ps1"))) {
    $candidate = Get-ChildItem -LiteralPath $extractDir -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "ccusage-setup-wizard.ps1")
    } | Select-Object -First 1
    if ($candidate) {
        $source = $candidate.FullName
    }
}

$wizard = Join-Path $source "ccusage-setup-wizard.ps1"
if (!(Test-Path -LiteralPath $wizard)) {
    throw "Setup-Assistent (ccusage-setup-wizard.ps1) wurde im Installationspaket nicht gefunden."
}

# Unblock all extracted files to be absolutely sure Smart App Control doesn't block them
Get-ChildItem -Path $source -Recurse | ForEach-Object {
    try { Unblock-File -LiteralPath $_.FullName } catch {}
}

Write-Host "Starte Setup-Assistenten..." -ForegroundColor Green

# Launch the wizard in a separate process and let it run
Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $wizard
)
