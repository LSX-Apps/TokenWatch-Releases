param(
    [switch]$Uninstall,
    [switch]$NoAutostart,
    [switch]$NoStart,
    [switch]$TestOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$AppName = "Claude Usage Tray"
$InstallDir = Join-Path $env:LOCALAPPDATA "ClaudeUsageTray"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartupDir = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "Claude Usage Tray.lnk"
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$DesktopShortcutPath = Join-Path $DesktopDir "Claude Usage Tray.lnk"
$PowerShellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$Files = @(
    "ccusage-poll.ps1",
    "ccusage-tray.ps1",
    "ccusage-update.ps1",
    "install-ccusage-windows.ps1",
    "ccusage-setup-wizard.ps1",
    "ClaudeUsageTray-Setup.cmd",
    "ClaudeUsageTray-Setup.lnk",
    "README.md",
    "RELEASE-HOWTO.md",
    "app-version.json"
)

function Stop-ExistingTray {
    try {
        $procs = Get-CimInstance Win32_Process | Where-Object {
            ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
            $_.CommandLine -and
            $_.CommandLine -like "*ccusage-tray.ps1*"
        }
        foreach ($proc in $procs) {
            try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
    } catch {}
}

function New-StartupShortcut {
    param([string]$TargetScript)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $PowerShellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TargetScript`""
    $shortcut.WorkingDirectory = Split-Path -Parent $TargetScript
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
    $shortcut.Description = "Claude Usage Tray starten"
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}

function New-DesktopShortcut {
    param([string]$TrayScript)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($DesktopShortcutPath)
    $shortcut.TargetPath = $PowerShellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
    $shortcut.WorkingDirectory = Split-Path -Parent $TrayScript
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
    $shortcut.Description = "Claude Usage Tray starten"
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}

function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR -and $env:CLAUDE_CONFIG_DIR.Trim().Length -gt 0) {
        return $env:CLAUDE_CONFIG_DIR
    }
    return (Join-Path $env:USERPROFILE ".claude")
}

function Show-CredentialHint {
    $credentialsPath = Join-Path (Get-ClaudeConfigDir) ".credentials.json"
    if (Test-Path -LiteralPath $credentialsPath) {
        Write-Host "Claude-Code-Credentials gefunden: $credentialsPath" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Hinweis: Es wurden noch keine Claude-Code-Credentials gefunden." -ForegroundColor Yellow
    Write-Host "Einmalig nötig:"
    Write-Host "  1. Claude Code installieren"
    Write-Host "  2. In PowerShell einmal 'claude' starten und den Browser-Login abschließen"
    Write-Host "  3. Danach dieses Install-Skript erneut ausführen oder im Tray 'Jetzt aktualisieren' klicken"
    Write-Host ""
}

if ($Uninstall) {
    Stop-ExistingTray
    if (Test-Path -LiteralPath $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
    }
    if (Test-Path -LiteralPath $DesktopShortcutPath) {
        Remove-Item -LiteralPath $DesktopShortcutPath -Force
    }
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Claude Usage Tray wurde erfolgreich deinstalliert.", "Claude Usage Tray", "OK", "Information") | Out-Null
    exit 0
}

if ($TestOnly) {
    & (Join-Path $SourceDir "ccusage-poll.ps1") -VerboseOutput
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

foreach ($file in $Files) {
    $src = Join-Path $SourceDir $file
    if (!(Test-Path -LiteralPath $src)) {
        throw "Quelldatei fehlt: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $file) -Force
    try { Unblock-File -LiteralPath (Join-Path $InstallDir $file) } catch {}
}

$configSrc = Join-Path $SourceDir "ccusage-config.json"
$configDest = Join-Path $InstallDir "ccusage-config.json"
if (Test-Path -LiteralPath $configSrc) {
    if (!(Test-Path -LiteralPath $configDest)) {
        Copy-Item -LiteralPath $configSrc -Destination $configDest -Force
    } else {
        try {
            $destConfig = Get-Content -LiteralPath $configDest -Raw | ConvertFrom-Json
            if (!$destConfig.update_manifest_url) {
                $srcConfigObj = Get-Content -LiteralPath $configSrc -Raw | ConvertFrom-Json
                if ($srcConfigObj.update_manifest_url) {
                    $destConfig.update_manifest_url = $srcConfigObj.update_manifest_url
                    $destConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configDest -Encoding UTF8
                    Write-Host "Update-URL in Konfiguration aktualisiert." -ForegroundColor Green
                }
            }
        } catch {}
    }
    try { Unblock-File -LiteralPath $configDest } catch {}
}

$trayScript = Join-Path $InstallDir "ccusage-tray.ps1"

if (!$NoAutostart) {
    New-StartupShortcut -TargetScript $trayScript
    Write-Host "Autostart angelegt: $ShortcutPath" -ForegroundColor Green
} else {
    Write-Host "Autostart wurde übersprungen."
}

New-DesktopShortcut -TrayScript $trayScript
Write-Host "Desktop-Verknüpfung angelegt: $DesktopShortcutPath" -ForegroundColor Green

Show-CredentialHint

if (!$NoStart) {
    Stop-ExistingTray
    Start-Process -FilePath $PowerShellExe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $trayScript
    ) -WindowStyle Hidden
    Write-Host "$AppName wurde gestartet." -ForegroundColor Green
}

Write-Host ""
Write-Host "Test manuell:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$InstallDir\ccusage-poll.ps1`" -VerboseOutput"
Write-Host ""
Write-Host "Deinstallieren:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Uninstall"
