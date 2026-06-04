Set-StrictMode -Version 2.0
$ErrorActionPreference = "Continue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $SourceDir "install-ccusage-windows.ps1"
$InstallDir = Join-Path $env:LOCALAPPDATA "ClaudeUsageTray"
$CredentialsPath = Join-Path $env:USERPROFILE ".claude\.credentials.json"

function Find-Claude {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = @(
        (Join-Path $env:USERPROFILE ".local\bin\claude.exe"),
        (Join-Path $env:USERPROFILE ".local\bin\claude"),
        (Join-Path $env:APPDATA "npm\claude.cmd"),
        (Join-Path $env:APPDATA "npm\claude.ps1")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-ClaudeCredentials {
    if (!(Test-Path -LiteralPath $CredentialsPath)) {
        return $false
    }

    try {
        $credentials = Get-Content -LiteralPath $CredentialsPath -Raw | ConvertFrom-Json
        return [bool]($credentials.claudeAiOauth.accessToken)
    } catch {
        return $false
    }
}

function Start-VisiblePowerShellScript {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptText
    )

    $tmp = Join-Path $env:TEMP ("ClaudeUsageTray-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    Set-Content -LiteralPath $tmp -Value $ScriptText -Encoding UTF8
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-File", $tmp
    )
}

function Show-Info {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "Claude Usage Tray", "OK", "Information") | Out-Null
}

function Show-Warn {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "Claude Usage Tray", "OK", "Warning") | Out-Null
}

# Theme Colors
$ColorBackground = [System.Drawing.Color]::FromArgb(18, 18, 20)      # Slate dark
$ColorCardBackground = [System.Drawing.Color]::FromArgb(26, 26, 30)  # Slightly lighter card dark
$ColorBorder = [System.Drawing.Color]::FromArgb(63, 63, 70)          # Zinc border
$ColorTextPrimary = [System.Drawing.Color]::FromArgb(244, 244, 245)   # Zinc-50
$ColorTextSecondary = [System.Drawing.Color]::FromArgb(161, 161, 170) # Zinc-400
$ColorGreen = [System.Drawing.Color]::FromArgb(16, 185, 129)          # Emerald-500
$ColorGreenHover = [System.Drawing.Color]::FromArgb(5, 150, 105)      # Emerald-600
$ColorRed = [System.Drawing.Color]::FromArgb(244, 63, 94)            # Rose-500
$ColorIndigo = [System.Drawing.Color]::FromArgb(99, 102, 241)        # Indigo-500
$ColorIndigoHover = [System.Drawing.Color]::FromArgb(79, 70, 229)   # Indigo-600
$ColorDarkGrey = [System.Drawing.Color]::FromArgb(39, 39, 42)        # Zinc-800
$ColorTextDisabled = [System.Drawing.Color]::FromArgb(113, 113, 122)  # Zinc-500

# Form setup
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Claude Usage Tray Setup"
$Form.StartPosition = "CenterScreen"
$Form.Size = New-Object System.Drawing.Size(720, 480)
$Form.MinimumSize = New-Object System.Drawing.Size(720, 480)
$Form.MaximumSize = New-Object System.Drawing.Size(720, 480)
$Form.BackColor = $ColorBackground
$Form.ForeColor = $ColorTextPrimary
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

# Top Accent Line
$AccentLine = New-Object System.Windows.Forms.Panel
$AccentLine.Size = New-Object System.Drawing.Size(720, 4)
$AccentLine.Location = New-Object System.Drawing.Point(0, 0)
$AccentLine.BackColor = $ColorIndigo
$Form.Controls.Add($AccentLine)

# Title
$Title = New-Object System.Windows.Forms.Label
$Title.Text = "Claude Usage Tray einrichten"
$Title.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$Title.AutoSize = $true
$Title.ForeColor = $ColorTextPrimary
$Title.Location = New-Object System.Drawing.Point(24, 16)
$Form.Controls.Add($Title)

# Intro Description
$Intro = New-Object System.Windows.Forms.Label
$Intro.Text = "Dieser Assistent installiert Claude Code, startet den Login und richtet danach das Tray-Icon für die Claude-Nutzung ein."
$Intro.AutoSize = $false
$Intro.Size = New-Object System.Drawing.Size(650, 32)
$Intro.ForeColor = $ColorTextSecondary
$Intro.Location = New-Object System.Drawing.Point(26, 52)
$Form.Controls.Add($Intro)

# Helper to style modern panels with borders
function Style-Panel {
    param($Panel)
    $Panel.BackColor = $ColorCardBackground
    $Panel.add_Paint({
        $pen = New-Object System.Drawing.Pen ($ColorBorder), 1
        $_.Graphics.DrawRectangle($pen, 0, 0, $this.Width - 1, $this.Height - 1)
        $pen.Dispose()
    })
}

# Helper to style modern flat buttons
function Style-Button {
    param(
        $Button, 
        $ActiveBg = $ColorIndigo, 
        $HoverBg = $ColorIndigoHover
    )
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $Button.BackColor = $ActiveBg
    $Button.ForeColor = [System.Drawing.Color]::White

    # Attach colors as NoteProperties so they are accessible inside event handler scope ($this)
    if (!($Button.PSObject.Properties["ActiveBg"])) {
        $Button | Add-Member -MemberType NoteProperty -Name "ActiveBg" -Value $ActiveBg -Force
        $Button | Add-Member -MemberType NoteProperty -Name "HoverBg" -Value $HoverBg -Force
    } else {
        $Button.ActiveBg = $ActiveBg
        $Button.HoverBg = $HoverBg
    }

    $Button.Add_MouseEnter({
        if ($this.Enabled) { $this.BackColor = $this.HoverBg }
    })
    $Button.Add_MouseLeave({
        if ($this.Enabled) { $this.BackColor = $this.ActiveBg }
    })
}

# Helper to update button enable state with premium coloring
function Set-ButtonEnabled {
    param(
        $Button, 
        [bool]$Enabled,
        $ActiveBg = $ColorIndigo,
        $HoverBg = $ColorIndigoHover
    )
    $Button.Enabled = $Enabled
    
    # Update properties so that the MouseEnter/Leave handlers use the new colors
    if (!($Button.PSObject.Properties["ActiveBg"])) {
        $Button | Add-Member -MemberType NoteProperty -Name "ActiveBg" -Value $ActiveBg -Force
        $Button | Add-Member -MemberType NoteProperty -Name "HoverBg" -Value $HoverBg -Force
    } else {
        $Button.ActiveBg = $ActiveBg
        $Button.HoverBg = $HoverBg
    }

    if ($Enabled) {
        $Button.BackColor = $Button.ActiveBg
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    } else {
        $Button.BackColor = $ColorDarkGrey
        $Button.ForeColor = $ColorTextDisabled
        $Button.Cursor = [System.Windows.Forms.Cursors]::No
    }
}

# --- CARD 1: Claude Code CLI ---
$Card1 = New-Object System.Windows.Forms.Panel
$Card1.Size = New-Object System.Drawing.Size(650, 85)
$Card1.Location = New-Object System.Drawing.Point(26, 95)
Style-Panel $Card1
$Form.Controls.Add($Card1)

$Step1Title = New-Object System.Windows.Forms.Label
$Step1Title.Text = "Schritt 1: Claude Code (CLI) installieren"
$Step1Title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$Step1Title.ForeColor = $ColorTextPrimary
$Step1Title.Location = New-Object System.Drawing.Point(18, 12)
$Step1Title.AutoSize = $true
$Card1.Controls.Add($Step1Title)

$ClaudeStatus = New-Object System.Windows.Forms.Label
$ClaudeStatus.AutoSize = $false
$ClaudeStatus.Size = New-Object System.Drawing.Size(410, 38)
$ClaudeStatus.Location = New-Object System.Drawing.Point(18, 38)
$ClaudeStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$Card1.Controls.Add($ClaudeStatus)

$InstallClaudeButton = New-Object System.Windows.Forms.Button
$InstallClaudeButton.Text = "Installieren"
$InstallClaudeButton.Size = New-Object System.Drawing.Size(160, 32)
$InstallClaudeButton.Location = New-Object System.Drawing.Point(472, 26)
Style-Button $InstallClaudeButton
$Card1.Controls.Add($InstallClaudeButton)


# --- CARD 2: Login Credentials ---
$Card2 = New-Object System.Windows.Forms.Panel
$Card2.Size = New-Object System.Drawing.Size(650, 85)
$Card2.Location = New-Object System.Drawing.Point(26, 190)
Style-Panel $Card2
$Form.Controls.Add($Card2)

$Step2Title = New-Object System.Windows.Forms.Label
$Step2Title.Text = "Schritt 2: Bei Claude anmelden"
$Step2Title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$Step2Title.ForeColor = $ColorTextPrimary
$Step2Title.Location = New-Object System.Drawing.Point(18, 12)
$Step2Title.AutoSize = $true
$Card2.Controls.Add($Step2Title)

$LoginStatus = New-Object System.Windows.Forms.Label
$LoginStatus.AutoSize = $false
$LoginStatus.Size = New-Object System.Drawing.Size(410, 38)
$LoginStatus.Location = New-Object System.Drawing.Point(18, 38)
$LoginStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$Card2.Controls.Add($LoginStatus)

$LoginButton = New-Object System.Windows.Forms.Button
$LoginButton.Text = "Login starten"
$LoginButton.Size = New-Object System.Drawing.Size(160, 32)
$LoginButton.Location = New-Object System.Drawing.Point(472, 26)
Style-Button $LoginButton
$Card2.Controls.Add($LoginButton)


# --- CARD 3: Tray App Installation ---
$Card3 = New-Object System.Windows.Forms.Panel
$Card3.Size = New-Object System.Drawing.Size(650, 85)
$Card3.Location = New-Object System.Drawing.Point(26, 285)
Style-Panel $Card3
$Form.Controls.Add($Card3)

$Step3Title = New-Object System.Windows.Forms.Label
$Step3Title.Text = "Schritt 3: Tray-App in Windows einrichten"
$Step3Title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$Step3Title.ForeColor = $ColorTextPrimary
$Step3Title.Location = New-Object System.Drawing.Point(18, 12)
$Step3Title.AutoSize = $true
$Card3.Controls.Add($Step3Title)

$InstallStatus = New-Object System.Windows.Forms.Label
$InstallStatus.AutoSize = $false
$InstallStatus.Size = New-Object System.Drawing.Size(410, 38)
$InstallStatus.Location = New-Object System.Drawing.Point(18, 38)
$InstallStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$Card3.Controls.Add($InstallStatus)

$InstallButton = New-Object System.Windows.Forms.Button
$InstallButton.Text = "Tray einrichten"
$InstallButton.Size = New-Object System.Drawing.Size(160, 32)
$InstallButton.Location = New-Object System.Drawing.Point(472, 26)
Style-Button $InstallButton
$Card3.Controls.Add($InstallButton)


# --- BOTTOM CONTROL BAR ---
$RefreshButton = New-Object System.Windows.Forms.Button
$RefreshButton.Text = "Erneut prüfen"
$RefreshButton.Size = New-Object System.Drawing.Size(140, 36)
$RefreshButton.Location = New-Object System.Drawing.Point(26, 388)
Style-Button $RefreshButton -ActiveBg $ColorDarkGrey -HoverBg $ColorBorder
$Form.Controls.Add($RefreshButton)

$ReadmeButton = New-Object System.Windows.Forms.Button
$ReadmeButton.Text = "Anleitung öffnen"
$ReadmeButton.Size = New-Object System.Drawing.Size(150, 36)
$ReadmeButton.Location = New-Object System.Drawing.Point(176, 388)
Style-Button $ReadmeButton -ActiveBg $ColorDarkGrey -HoverBg $ColorBorder
$Form.Controls.Add($ReadmeButton)

$CloseButton = New-Object System.Windows.Forms.Button
$CloseButton.Text = "Installation beenden"
$CloseButton.Size = New-Object System.Drawing.Size(200, 36)
$CloseButton.Location = New-Object System.Drawing.Point(476, 388)
# Finish button uses green styling when active, gray when inactive
Style-Button $CloseButton -ActiveBg $ColorGreen -HoverBg $ColorGreenHover
$Form.Controls.Add($CloseButton)


# State Refresh Logic
function Refresh-State {
    $claudePath = Find-Claude
    $hasClaude = [bool]$claudePath
    $hasCreds = Test-ClaudeCredentials
    $isInstalled = Test-Path -LiteralPath (Join-Path $InstallDir "ccusage-tray.ps1")

    # Step 1 Update
    if ($hasClaude) {
        $ClaudeStatus.Text = "Bereit. Claude Code gefunden unter:`n$claudePath"
        $ClaudeStatus.ForeColor = $ColorGreen
    } else {
        $ClaudeStatus.Text = "Ausstehend. Claude Code ist noch nicht installiert."
        $ClaudeStatus.ForeColor = $ColorTextSecondary
    }

    # Step 2 Update
    if ($hasCreds) {
        $LoginStatus.Text = "Bereit. Anmeldedaten (.credentials.json) gefunden."
        $LoginStatus.ForeColor = $ColorGreen
    } else {
        if (!$hasClaude) {
            $LoginStatus.Text = "Gesperrt. Bitte führe zuerst Schritt 1 aus."
            $LoginStatus.ForeColor = $ColorTextDisabled
        } else {
            $LoginStatus.Text = "Ausstehend. Bitte logge dich über den Button ein."
            $LoginStatus.ForeColor = $ColorTextSecondary
        }
    }

    # Step 3 Update
    if ($isInstalled) {
        $InstallStatus.Text = "Bereit. Die App ist im System installiert."
        $InstallStatus.ForeColor = $ColorGreen
    } else {
        if (!$hasCreds) {
            $InstallStatus.Text = "Gesperrt. Bitte führe zuerst Schritt 2 aus."
            $InstallStatus.ForeColor = $ColorTextDisabled
        } else {
            $InstallStatus.Text = "Ausstehend. Klicke auf 'Tray einrichten' zum Installieren."
            $InstallStatus.ForeColor = $ColorTextSecondary
        }
    }

    # Control Enabling & Styling Constraints
    Set-ButtonEnabled -Button $LoginButton -Enabled $hasClaude
    Set-ButtonEnabled -Button $InstallButton -Enabled $hasCreds

    # Final "Finish" button constraint: Only enabled when step 3 is done!
    if ($isInstalled) {
        $CloseButton.Text = "Fertig stellen"
        Set-ButtonEnabled -Button $CloseButton -Enabled $true -ActiveBg $ColorGreen -HoverBg $ColorGreenHover
    } else {
        $CloseButton.Text = "Installation beenden"
        # We allow them to close (cancel) the installer, but colored as neutral gray rather than positive green
        Set-ButtonEnabled -Button $CloseButton -Enabled $true -ActiveBg $ColorDarkGrey -HoverBg $ColorBorder
    }
}


# Click Handlers
$InstallClaudeButton.Add_Click({
    $script = @'
Write-Host ""
Write-Host "Claude Code wird installiert..." -ForegroundColor Cyan
Write-Host "Quelle: https://claude.ai/install.ps1" -ForegroundColor Gray
Write-Host ""
try {
  irm https://claude.ai/install.ps1 | iex
  Write-Host ""
  Write-Host "Installation erfolgreich beendet!" -ForegroundColor Green
  Write-Host "Du kannst dieses Fenster jetzt schließen und im Setup 'Erneut prüfen' klicken." -ForegroundColor Gray
} catch {
  Write-Host ""
  Write-Host "Installation fehlgeschlagen:" -ForegroundColor Red
  Write-Host $_ -ForegroundColor Red
}
Write-Host ""
'@
    Start-VisiblePowerShellScript -ScriptText $script
    Show-Info "Es wurde ein Terminal geöffnet. Warte, bis die Installation dort fertig ist, schließe das Terminal und klicke hier auf 'Erneut prüfen'."
})

$LoginButton.Add_Click({
    $claude = Find-Claude
    if (!$claude) {
        Show-Warn "Claude Code wurde noch nicht gefunden. Bitte zuerst Schritt 1 ausführen."
        return
    }

    $script = @"
Write-Host ""
Write-Host "Claude Code Login startet..." -ForegroundColor Cyan
Write-Host "Wenn ein Browserfenster aufgeht, dort anmelden und Zugriff erlauben." -ForegroundColor Gray
Write-Host ""
& "$claude"
Write-Host ""
Write-Host "Wenn der Login fertig ist, dieses Fenster schließen und im Setup 'Erneut prüfen' klicken." -ForegroundColor Gray
"@
    Start-VisiblePowerShellScript -ScriptText $script
})

$InstallButton.Add_Click({
    if (!(Test-Path -LiteralPath $InstallScript)) {
        Show-Warn "Installationsdatei fehlt: $InstallScript"
        return
    }

    try {
        & $InstallScript
        Show-Info "Die Tray-App wurde erfolgreich eingerichtet und im Hintergrund gestartet. Das Icon befindet sich unten rechts in der Windows-Taskleiste."
    } catch {
        Show-Warn "Installation fehlgeschlagen: $_"
    }
    Refresh-State
})

$RefreshButton.Add_Click({ Refresh-State })

$ReadmeButton.Add_Click({
    $readme = Join-Path $SourceDir "README.md"
    if (Test-Path -LiteralPath $readme) {
        Start-Process notepad.exe $readme
    }
})

$CloseButton.Add_Click({
    $claudePath = Find-Claude
    $hasCreds = Test-ClaudeCredentials
    $isInstalled = Test-Path -LiteralPath (Join-Path $InstallDir "ccusage-tray.ps1")

    if ($isInstalled) {
        $Form.Close()
    } else {
        # Show warning that setup is not fully completed before exiting
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Die Installation ist noch nicht vollständig eingerichtet. Möchtest du das Setup wirklich abbrechen?", 
            "Setup abbrechen", 
            "YesNo", 
            "Question"
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $Form.Close()
        }
    }
})

$Form.Add_Shown({ Refresh-State })
[System.Windows.Forms.Application]::Run($Form)
