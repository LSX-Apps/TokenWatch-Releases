param(
    [switch]$NoRefresh,
    [switch]$Raw,
    [switch]$VerboseOutput,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
$OAuthScope = "user:profile user:inference user:sessions:claude_code user:mcp_servers"
$UsageUrl = "https://api.anthropic.com/api/oauth/usage"
$TokenUrl = "https://platform.claude.com/v1/oauth/token"

function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR -and $env:CLAUDE_CONFIG_DIR.Trim().Length -gt 0) {
        return $env:CLAUDE_CONFIG_DIR
    }
    return (Join-Path $env:USERPROFILE ".claude")
}

function Get-UsageDataPath {
    return (Join-Path (Get-ClaudeConfigDir) "cc-usage.json")
}

function Get-CredentialsPath {
    return (Join-Path (Get-ClaudeConfigDir) ".credentials.json")
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (!(Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $tmp = "$Path.tmp"
    $json = $Object | ConvertTo-Json -Depth 30
    Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-State {
    param(
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$Message,
        [int]$ExitCode = 1,
        [long]$BackoffUntilMs = 0
    )

    $dataPath = Get-UsageDataPath
    $existing = $null
    if (Test-Path -LiteralPath $dataPath) {
        try {
            $existing = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
        } catch {}
    }

    $state = [ordered]@{
        status = $Status
        message = $Message
        updated_at = ([DateTimeOffset]::UtcNow.ToString("o"))
        source = "ccusage-poll"
    }

    if ($BackoffUntilMs -gt 0) {
        $state | Add-Member -MemberType NoteProperty -Name "backoff_until_ms" -Value $BackoffUntilMs
    } elseif ($existing -and $existing.PSObject.Properties["backoff_until_ms"]) {
        $state | Add-Member -MemberType NoteProperty -Name "backoff_until_ms" -Value $existing.backoff_until_ms
    }

    if ($Status -eq "error" -and $existing) {
        $props = @("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps", "extra_usage", "plan")
        foreach ($p in $props) {
            if ($existing.PSObject.Properties[$p]) {
                $state | Add-Member -MemberType NoteProperty -Name $p -Value $existing.$p
            }
        }
    }

    Write-JsonFile -Object $state -Path $dataPath
    if ($VerboseOutput) {
        $state | ConvertTo-Json -Depth 10
    }
    exit $ExitCode
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Get-ClaudeVersion {
    try {
        $cmd = Get-Command claude -ErrorAction SilentlyContinue
        if (!$cmd) {
            return $null
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cmd.Source
        $psi.Arguments = "--version"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        if (!$p.WaitForExit(2500)) {
            try { $p.Kill() } catch {}
            return $null
        }
        $out = ($p.StandardOutput.ReadToEnd() + " " + $p.StandardError.ReadToEnd()).Trim()
        if ($out -match "([0-9]+\.[0-9]+\.[0-9]+)") {
            return $matches[1]
        }
    } catch {}
    return $null
}

function Get-UserAgent {
    if ($env:CC_USAGE_USER_AGENT -and $env:CC_USAGE_USER_AGENT.Trim().Length -gt 0) {
        return $env:CC_USAGE_USER_AGENT
    }

    $version = Get-ClaudeVersion
    if (!$version) {
        $version = "2.1.0"
    }
    return "claude-code/$version"
}

function Invoke-JsonRequest {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("GET","POST")][string]$Method,
        [Parameter(Mandatory=$true)][string]$Uri,
        [hashtable]$Headers,
        [string]$Body,
        [string]$UserAgent
    )

    try {
        if ($Method -eq "POST") {
            return Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers -Body $Body -ContentType "application/json" -UserAgent $UserAgent
        }
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -UserAgent $UserAgent
    } catch {
        $status = $null
        $bodyText = $null
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $bodyText = $reader.ReadToEnd()
                }
            } catch {}
        }
        $msg = $_.Exception.Message
        if ($status) { $msg = "HTTP $status - $msg" }
        if ($bodyText) { $msg = "$msg - $bodyText" }
        throw $msg
    }
}

function Convert-UsageWindow {
    param($Window)

    if (!$Window) {
        return $null
    }

    $util = $null
    if ($Window.PSObject.Properties.Name -contains "utilization") {
        $util = $Window.utilization
    } elseif ($Window.PSObject.Properties.Name -contains "used_percentage") {
        $util = $Window.used_percentage
    }

    $resetRaw = $null
    if ($Window.PSObject.Properties.Name -contains "resets_at") {
        $resetRaw = $Window.resets_at
    }

    $resetUtc = $null
    $resetLocal = $null
    if ($resetRaw) {
        try {
            $dto = [DateTimeOffset]::Parse([string]$resetRaw)
            $resetUtc = $dto.UtcDateTime.ToString("o")
            $resetLocal = $dto.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz")
        } catch {
            $resetUtc = [string]$resetRaw
        }
    }

    $pct = $null
    if ($null -ne $util) {
        try { $pct = [int][Math]::Round([double]$util) } catch {}
    }

    return [ordered]@{
        used_percentage = $pct
        resets_at_utc = $resetUtc
        resets_at_local = $resetLocal
        raw_utilization = $util
    }
}

function Refresh-ClaudeTokenIfNeeded {
    param(
        [Parameter(Mandatory=$true)]$Credentials,
        [Parameter(Mandatory=$true)][string]$CredentialsPath,
        [Parameter(Mandatory=$true)][string]$UserAgent
    )

    $oauth = $Credentials.claudeAiOauth
    if (!$oauth) {
        Write-State -Status "missing_oauth" -Message "In .credentials.json wurde kein claudeAiOauth-Block gefunden." -ExitCode 3
    }

    $accessToken = $oauth.accessToken
    $refreshToken = $oauth.refreshToken
    if (!$accessToken) {
        Write-State -Status "missing_token" -Message "In .credentials.json fehlt claudeAiOauth.accessToken." -ExitCode 3
    }

    if ($NoRefresh -or !$refreshToken) {
        return $accessToken
    }

    $expiresAt = $null
    try { $expiresAt = [Int64]$oauth.expiresAt } catch {}
    if (!$expiresAt) {
        return $accessToken
    }

    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $refreshAtMs = $nowMs + (5 * 60 * 1000)
    if ($expiresAt -gt $refreshAtMs) {
        return $accessToken
    }

    $headers = @{
        "Accept" = "application/json"
    }
    $bodyObj = [ordered]@{
        grant_type = "refresh_token"
        refresh_token = $refreshToken
        client_id = $ClientId
        scope = $OAuthScope
    }
    $body = $bodyObj | ConvertTo-Json -Compress

    $response = Invoke-JsonRequest -Method POST -Uri $TokenUrl -Headers $headers -Body $body -UserAgent $UserAgent

    if (!$response.access_token) {
        throw "Token-Refresh hat keine access_token-Antwort geliefert."
    }

    $backup = "$CredentialsPath.bak-ccusage"
    if (!(Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $CredentialsPath -Destination $backup -Force
    }

    Set-ObjectProperty -Object $oauth -Name "accessToken" -Value $response.access_token
    if ($response.refresh_token) {
        Set-ObjectProperty -Object $oauth -Name "refreshToken" -Value $response.refresh_token
    }
    $expiresIn = 3600
    try {
        if ($response.expires_in) { $expiresIn = [int]$response.expires_in }
    } catch {}
    Set-ObjectProperty -Object $oauth -Name "expiresAt" -Value ([DateTimeOffset]::UtcNow.AddSeconds($expiresIn).ToUnixTimeMilliseconds())

    Write-JsonFile -Object $Credentials -Path $CredentialsPath
    return $response.access_token
}

$mutex = New-Object System.Threading.Mutex($false, "ClaudeUsagePoller-$env:USERNAME")
$hasMutex = $false

try {
    $hasMutex = $mutex.WaitOne(0)
    if (!$hasMutex) {
        Write-State -Status "busy" -Message "Ein anderer Poller laeuft bereits." -ExitCode 0
    }

    $dataPath = Get-UsageDataPath
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if (!$Force -and (Test-Path -LiteralPath $dataPath)) {
        try {
            $existing = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
            if ($existing -and $existing.PSObject.Properties["backoff_until_ms"]) {
                $backoffUntil = [long]$existing.backoff_until_ms
                if ($nowMs -lt $backoffUntil) {
                    if ($VerboseOutput) {
                        Write-Host "Pausiert wegen Rate-Limit (Backoff bis $([DateTimeOffset]::FromUnixTimeMilliseconds($backoffUntil).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')))."
                    }
                    exit 0
                }
            }
        } catch {}
    }

    $credentialsPath = Get-CredentialsPath
    if (!(Test-Path -LiteralPath $credentialsPath)) {
        Write-State -Status "missing_credentials" -Message "Claude-Code-Credentials fehlen. Installiere Claude Code und fuehre einmal 'claude' aus, um dich einzuloggen." -ExitCode 3
    }

    $credentials = Get-Content -LiteralPath $credentialsPath -Raw | ConvertFrom-Json
    $userAgent = Get-UserAgent
    $token = Refresh-ClaudeTokenIfNeeded -Credentials $credentials -CredentialsPath $credentialsPath -UserAgent $userAgent

    $headers = @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $token"
        "anthropic-beta" = "oauth-2025-04-20"
    }

    $usage = Invoke-JsonRequest -Method GET -Uri $UsageUrl -Headers $headers -UserAgent $userAgent

    if ($Raw) {
        $usage | ConvertTo-Json -Depth 30
        exit 0
    }

    $state = [ordered]@{
        status = "ok"
        updated_at = ([DateTimeOffset]::UtcNow.ToString("o"))
        updated_at_local = ([DateTimeOffset]::Now.ToString("yyyy-MM-dd HH:mm:ss zzz"))
        source = "anthropic-oauth-usage"
        user_agent = $userAgent
        plan = [ordered]@{
            subscription_type = $credentials.claudeAiOauth.subscriptionType
            rate_limit_tier = $credentials.claudeAiOauth.rateLimitTier
        }
        five_hour = Convert-UsageWindow -Window $usage.five_hour
        seven_day = Convert-UsageWindow -Window $usage.seven_day
        seven_day_opus = Convert-UsageWindow -Window $usage.seven_day_opus
        seven_day_sonnet = Convert-UsageWindow -Window $usage.seven_day_sonnet
        seven_day_oauth_apps = Convert-UsageWindow -Window $usage.seven_day_oauth_apps
        extra_usage = $usage.extra_usage
    }

    Write-JsonFile -Object $state -Path (Get-UsageDataPath)

    if ($VerboseOutput) {
        $state | ConvertTo-Json -Depth 30
    }
    exit 0
} catch {
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $errStr = [string]$_
    $backoffDuration = 10 * 60 * 1000 # Default: 10 minutes

    if ($errStr -match "429" -or $errStr -match "rate_limit" -or $errStr -match "Too Many Requests") {
        $backoffDuration = 30 * 60 * 1000 # Rate limit backoff: 30 minutes
    }

    $backoffUntil = $nowMs + $backoffDuration
    Write-State -Status "error" -Message $errStr -ExitCode 1 -BackoffUntilMs $backoffUntil
} finally {
    if ($hasMutex) {
        try { $mutex.ReleaseMutex() | Out-Null } catch {}
    }
    $mutex.Dispose()
}

