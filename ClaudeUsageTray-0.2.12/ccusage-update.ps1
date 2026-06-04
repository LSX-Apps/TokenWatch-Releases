param(
    [switch]$Interactive,
    [string]$ManifestUrl,
    [switch]$SilentIfLatest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $InstallDir "ccusage-config.json"
$VersionPath = Join-Path $InstallDir "app-version.json"
$PowerShellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

function Show-Message {
    param(
        [string]$Text,
        [string]$Title = "Claude Usage Tray Update",
        [string]$Icon = "Information"
    )

    if ($Interactive) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Text, $Title, "OK", $Icon) | Out-Null
    } else {
        Write-Host $Text
    }
}

function Ask-YesNo {
    param([string]$Text)

    if ($Interactive) {
        Add-Type -AssemblyName System.Windows.Forms
        $result = [System.Windows.Forms.MessageBox]::Show($Text, "Claude Usage Tray Update", "YesNo", "Question")
        return $result -eq [System.Windows.Forms.DialogResult]::Yes
    }

    $answer = Read-Host "$Text [j/N]"
    return $answer -match "^(j|ja|y|yes)$"
}

function Get-CurrentVersion {
    if (!(Test-Path -LiteralPath $VersionPath)) {
        return "0.0.0"
    }
    try {
        return (Get-Content -LiteralPath $VersionPath -Raw | ConvertFrom-Json).version
    } catch {
        return "0.0.0"
    }
}

function Get-ManifestUrl {
    if ($ManifestUrl) {
        return $ManifestUrl
    }
    if (!(Test-Path -LiteralPath $ConfigPath)) {
        return ""
    }
    try {
        return (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).update_manifest_url
    } catch {
        return ""
    }
}

function Stop-Tray {
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

function Start-Tray {
    $tray = Join-Path $InstallDir "ccusage-tray.ps1"
    if (Test-Path -LiteralPath $tray) {
        Start-Process -FilePath $PowerShellExe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", $tray
        ) -WindowStyle Hidden
    }
}

try {
    $url = Get-ManifestUrl
    if (!$url) {
        Show-Message "Es ist noch keine Update-Adresse eingerichtet. Für Updates musst du eine Manifest-URL in ccusage-config.json setzen." "Claude Usage Tray Update" "Warning"
        exit 2
    }

    $current = Get-CurrentVersion
    $manifest = Invoke-RestMethod -Uri $url -UseBasicParsing
    $latest = [string]$manifest.version
    $downloadUrl = [string]$manifest.download_url

    if (!$latest -or !$downloadUrl) {
        throw "Manifest muss 'version' und 'download_url' enthalten."
    }

    if ([version]$latest -le [version]$current) {
        if (!$SilentIfLatest) {
            Show-Message "Du hast bereits die aktuelle Version ($current)."
        }
        exit 0
    }

    $notes = ""
    if ($manifest.notes) { $notes = "`n`nÄnderungen:`n$($manifest.notes)" }
    if (!(Ask-YesNo "Update gefunden: $current -> $latest.$notes`n`nJetzt installieren?")) {
        exit 0
    }

    $tempDir = Join-Path $env:TEMP ("ClaudeUsageTrayUpdate-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $zipPath = Join-Path $tempDir "update.zip"

    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    if ($manifest.sha256) {
        $stream = [System.IO.File]::OpenRead($zipPath)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($stream)
        $stream.Close()
        $actualHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()

        $expectedHash = ([string]$manifest.sha256).ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "SHA256 passt nicht. Erwartet $expectedHash, bekommen $actualHash."
        }
    }

    $extractDir = Join-Path $tempDir "extract"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $source = $extractDir
    if (!(Test-Path -LiteralPath (Join-Path $source "ccusage-tray.ps1"))) {
        $candidate = Get-ChildItem -LiteralPath $extractDir -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "ccusage-tray.ps1")
        } | Select-Object -First 1
        if ($candidate) {
            $source = $candidate.FullName
        }
    }

    if (!(Test-Path -LiteralPath (Join-Path $source "ccusage-tray.ps1"))) {
        throw "Update-ZIP enthält keine ccusage-tray.ps1."
    }

    Stop-Tray

    $files = @(
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

    foreach ($file in $files) {
        $src = Join-Path $source $file
        if (Test-Path -LiteralPath $src) {
            $dest = Join-Path $InstallDir $file
            Copy-Item -LiteralPath $src -Destination $dest -Force
            try { Unblock-File -LiteralPath $dest } catch {}
        }
    }

    $srcConfig = Join-Path $source "ccusage-config.json"
    if (Test-Path -LiteralPath $srcConfig) {
        if (!(Test-Path -LiteralPath $ConfigPath)) {
            Copy-Item -LiteralPath $srcConfig -Destination $ConfigPath -Force
        } else {
            try {
                $destConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
                if (!$destConfig.update_manifest_url) {
                    $srcConfigObj = Get-Content -LiteralPath $srcConfig -Raw | ConvertFrom-Json
                    if ($srcConfigObj.update_manifest_url) {
                        $destConfig.update_manifest_url = $srcConfigObj.update_manifest_url
                        $destConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
                    }
                }
            } catch {}
        }
        try { Unblock-File -LiteralPath $ConfigPath } catch {}
    }

    Start-Tray
    Show-Message "Update auf Version $latest wurde installiert."
    exit 0
} catch {
    Show-Message "Update fehlgeschlagen:`n$_" "Claude Usage Tray Update" "Error"
    exit 1
}
