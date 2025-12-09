# CyberArk Fuzzy API - Authentication Module

# Note: Config and Api modules must be loaded before this module
# The using module statements are handled in Main.ps1

class AuthManager {
    [object]$Config  # Using object to avoid parse-time type requirement
    [object]$Api     # Using object to avoid parse-time type requirement
    
    AuthManager([object]$config, [object]$api) {  # Using object to avoid parse-time type requirement
        # Runtime type checks using type name strings
        if ($config.GetType().Name -ne "Config") {
            throw "Config parameter must be of type Config"
        }
        if ($api.GetType().Name -ne "CyberArkAPI") {
            throw "Api parameter must be of type CyberArkAPI"
        }
        $this.Config = $config
        $this.Api = $api
    }
    
    [string] GetPassword() {
        # Try Windows Credential Manager first (if module is available)
        try {
            $credModule = Get-Module -ListAvailable -Name CredentialManager
            if ($credModule) {
                Import-Module CredentialManager -ErrorAction SilentlyContinue
                $cred = Get-StoredCredential -Target "cyberark-fuzzy-$($this.Config.Username)" -ErrorAction SilentlyContinue
                if ($cred) {
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
                    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
                    return $password
                }
            }
        }
        catch {
            # Credential Manager not available or not found
        }
        
        # Fall back to secure prompt
        $securePassword = Read-Host "Password for $($this.Config.Username)" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        return $password
    }
    
    [void] SavePassword([string]$password) {
        try {
            $credModule = Get-Module -ListAvailable -Name CredentialManager
            if (-not $credModule) {
                Write-Host "CredentialManager module not found. Install it with: Install-Module -Name CredentialManager" -ForegroundColor Yellow
                return
            }
            
            Import-Module CredentialManager -ErrorAction Stop
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($this.Config.Username, $securePassword)
            Set-StoredCredential -Target "cyberark-fuzzy-$($this.Config.Username)" -Credential $cred -Persist LocalMachine -ErrorAction Stop
            Write-Host "Password saved to credential store" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not save password: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    [bool] Authenticate([bool]$savePassword = $false) {
        $password = $this.GetPassword()
        
        try {
            Write-Host "Authenticating as $($this.Config.Username)..." -ForegroundColor Cyan
            # Use reflection to call LogonRadius to bypass parameter resolution issues
            # when classes are loaded via Invoke-Expression
            $logonMethod = $this.Api.GetType().GetMethod("LogonRadius")
            if ($logonMethod) {
                # Explicitly pass all 3 parameters: username, password, concurrent
                $logonMethod.Invoke($this.Api, @($this.Config.Username, $password, $true))
            } else {
                # Fallback to direct call if reflection fails
                $this.Api.LogonRadius($this.Config.Username, $password, $true)
            }
            Write-Host "Authentication successful" -ForegroundColor Green
            
            if ($savePassword) {
                $this.SavePassword($password)
            }
            
            return $true
        }
        catch {
            Write-Host "Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    [bool] CheckAndRefresh() {
        if ($this.Api.VerifySession()) {
            return $true
        }
        
        Write-Host "Session expired, re-authenticating..." -ForegroundColor Yellow
        # Use reflection to call Authenticate to bypass parameter resolution issues
        # when classes are loaded via Invoke-Expression
        $authenticateMethod = $this.GetType().GetMethod("Authenticate")
        if ($authenticateMethod) {
            return $authenticateMethod.Invoke($this, @($false))
        } else {
            # Fallback to direct call if reflection fails
            return $this.Authenticate($false)
        }
    }
    
    # Background Job Keepalive Management
    [object]$KeepaliveJob = $null
    
    [void] StartKeepalive([double]$timeoutHours = $null) {
        if ($timeoutHours -eq $null) {
            $timeoutHours = $this.Config.KeepaliveTimeoutHours
        }
        
        # Stop any existing keepalive job
        if ($this.KeepaliveJob) {
            $this.StopKeepalive()
        }
        
        $timeoutSeconds = [int]($timeoutHours * 3600)
        $endpoint = $this.Config.Endpoint
        $minInterval = $this.Config.KeepaliveMinSeconds
        $maxInterval = $this.Config.KeepaliveMaxSeconds
        $projectRoot = [string]$this.Config.GetConfigDir()
        $tokenPath = Join-Path -Path $projectRoot -ChildPath "token"
        $logPath = Join-Path -Path $projectRoot -ChildPath "keepalive.log"
        $verifySSL = $this.Config.VerifySSL
        
        # Create keepalive script block
        $keepaliveScript = {
            param(
                [string]$Endpoint,
                [int]$TimeoutSeconds,
                [int]$MinInterval,
                [int]$MaxInterval,
                [string]$TokenPath,
                [string]$LogPath,
                [bool]$VerifySSL
            )
            
            function Write-Log {
                param([string]$Message)
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "$timestamp $Message" | Add-Content -Path $LogPath
            }
            
            function Ping-API {
                param(
                    [string]$Endpoint,
                    [string]$Token,
                    [bool]$VerifySSL
                )
                
                $url = "https://$Endpoint/PasswordVault/API/Safes"
                $headers = @{
                    "Authorization" = $Token
                    "Content-Type" = "application/json"
                }
                
                try {
                    $params = @{
                        Uri = $url
                        Method = "GET"
                        Headers = $headers
                        Body = @{limit = 1}
                        TimeoutSec = 30
                    }
                    if (-not $VerifySSL) {
                        $params.SkipCertificateCheck = $true
                    }
                    $response = Invoke-RestMethod @params
                    return $true
                }
                catch {
                    return $false
                }
            }
            
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
                if (-not (Test-Path $TokenPath)) {
                    Write-Log "Token file missing, exiting"
                    break
                }
                
                $token = (Get-Content $TokenPath -Raw).Trim()
                if ([string]::IsNullOrWhiteSpace($token)) {
                    Write-Log "Token is empty, exiting"
                    break
                }
                
                # Ping the API
                if (Ping-API -Endpoint $Endpoint -Token $token -VerifySSL $VerifySSL) {
                    Write-Log "Keepalive ping successful (elapsed: $([math]::Round($elapsed.TotalHours, 1))h)"
                }
                else {
                    Write-Log "Keepalive ping failed - token expired or invalid, exiting"
                    break
                }
            }
            
            Write-Log "Keepalive completed"
        }
        
        # Start the keepalive as a background job
        try {
            $this.KeepaliveJob = Start-Job -ScriptBlock $keepaliveScript -ArgumentList @(
                $endpoint,
                $timeoutSeconds,
                $minInterval,
                $maxInterval,
                $tokenPath,
                $logPath,
                $verifySSL
            )
            Write-Host "Token keepalive background job started (timeout: ${timeoutHours}h, Job ID: $($this.KeepaliveJob.Id))" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to start keepalive job: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] StopKeepalive() {
        if ($this.KeepaliveJob) {
            try {
                Stop-Job -Job $this.KeepaliveJob -ErrorAction SilentlyContinue
                Remove-Job -Job $this.KeepaliveJob -Force -ErrorAction SilentlyContinue
                Write-Host "Keepalive background job stopped" -ForegroundColor Yellow
            }
            catch {
                Write-Host "Could not stop keepalive job: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            finally {
                $this.KeepaliveJob = $null
            }
        }
    }
    
    [bool] IsKeepaliveRunning() {
        if (-not $this.KeepaliveJob) {
            return $false
        }
        
        $job = Get-Job -Id $this.KeepaliveJob.Id -ErrorAction SilentlyContinue
        return ($job -and $job.State -eq "Running")
    }
    
    # SSH Key Management
    [bool] DownloadSSHKey() {
        $keyPath = $this.Config.SSHKeyPath
        
        # Check if existing key is still valid
        if (Test-Path $keyPath) {
            $keyAge = (Get-Date) - (Get-Item $keyPath).LastWriteTime
            $keyAgeHours = $keyAge.TotalHours
            
            if ($keyAgeHours -lt $this.Config.KeyMaxAgeHours) {
                Write-Host "SSH key is $([math]::Round($keyAgeHours, 1)) hours old, still valid" -ForegroundColor Cyan
                return $true
            }
            Write-Host "SSH key is $([math]::Round($keyAgeHours, 1)) hours old, refreshing..." -ForegroundColor Yellow
        }
        else {
            Write-Host "No SSH key found, downloading..." -ForegroundColor Cyan
        }
        
        try {
            $privateKey = $this.Api.GetSSHKey()
            if (-not $privateKey) {
                Write-Host "Failed to retrieve SSH key" -ForegroundColor Red
                return $false
            }
            
            # Ensure directory exists
            $keyDir = Split-Path -Parent $keyPath
            if (-not (Test-Path $keyDir)) {
                New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
            }
            
            # Save key with restrictive permissions
            Set-Content -Path $keyPath -Value $privateKey -NoNewline
            $acl = Get-Acl $keyPath
            $acl.SetAccessRuleProtection($true, $false)
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, "FullControl", "Allow")
            $acl.SetAccessRule($accessRule)
            Set-Acl -Path $keyPath -AclObject $acl
            
            Write-Host "SSH key saved to $keyPath" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Failed to download SSH key: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
}

# Classes are automatically exported in PowerShell 5.1+
# No need for Export-ModuleMember -Class

