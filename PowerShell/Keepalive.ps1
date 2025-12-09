# CyberArk Fuzzy API - Keepalive Script for Scheduled Task
# This script is run by a Windows Scheduled Task to keep the API token alive

param(
    [Parameter(Mandatory=$true)]
    [string]$Endpoint,
    
    [Parameter(Mandatory=$true)]
    [int]$TimeoutSeconds,
    
    [int]$MinInterval = 901,   # 15:01
    [int]$MaxInterval = 1139   # 18:59
)

# Get project root (parent of PowerShell directory)
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath

# Ensure paths are strings, not arrays
if ($scriptPath -is [array]) {
    $scriptPath = $scriptPath[0]
}
if ($projectRoot -is [array]) {
    $projectRoot = $projectRoot[0]
}
$scriptPath = [string]$scriptPath
$projectRoot = [string]$projectRoot

# Import modules in dependency order
$modulesPath = Join-Path -Path $scriptPath -ChildPath "Modules"
Import-Module (Join-Path -Path $modulesPath -ChildPath "Config.psm1") -Force -Global
Import-Module (Join-Path -Path $modulesPath -ChildPath "Api.psm1") -Force -Global

# Paths
$tokenPath = Join-Path -Path $projectRoot -ChildPath "token"
$logPath = Join-Path -Path $projectRoot -ChildPath "keepalive.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$[$timestamp] $Message" | Add-Content -Path $logPath
}

function Ping-API {
    param(
        [string]$Endpoint,
        [string]$Token,
        [bool]$VerifySSL = $false
    )
    
    $url = "https://$Endpoint/PasswordVault/API/Safes"
    $headers = @{
        "Authorization" = $Token
        "Content-Type" = "application/json"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers -Body @{limit = 1} -SkipCertificateCheck:(-not $VerifySSL) -TimeoutSec 30
        return $true
    }
    catch {
        return $false
    }
}

# Initialize log
Write-Log "Keepalive started for endpoint: $Endpoint"
Write-Log "Hard timeout: ${TimeoutSeconds}s ($([math]::Round($TimeoutSeconds/3600, 1)) hours)"
Write-Log "PID: $PID"

$startTime = Get-Date
$random = New-Object System.Random

while ($true) {
    $elapsed = (Get-Date) - $startTime
    $remaining = $TimeoutSeconds - $elapsed.TotalSeconds
    
    # Check hard timeout
    if ($remaining -le 0) {
        Write-Log "Hard timeout reached ($TimeoutSeconds s), exiting"
        break
    }
    
    # Random sleep between min and max interval
    $sleepTime = [math]::Min($random.Next($MinInterval, $MaxInterval), [int]$remaining)
    
    Write-Log "Sleeping ${sleepTime}s (remaining: $([math]::Round($remaining/3600, 1))h)"
    Start-Sleep -Seconds $sleepTime
    
    # Check timeout again after sleep
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalSeconds -ge $TimeoutSeconds) {
        Write-Log "Hard timeout reached after sleep, exiting"
        break
    }
    
    # Read fresh token from file
    if (-not (Test-Path $tokenPath)) {
        Write-Log "Token file missing, exiting"
        exit 1
    }
    
    $token = (Get-Content $tokenPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Log "Token is empty, exiting"
        exit 1
    }
    
    # Ping the API
    if (Ping-API -Endpoint $Endpoint -Token $token) {
        Write-Log "Keepalive ping successful (elapsed: $([math]::Round($elapsed.TotalHours, 1))h)"
    }
    else {
        Write-Log "Keepalive ping failed - token expired or invalid, exiting"
        exit 1
    }
}

Write-Log "Keepalive completed"

