# CyberArk Fuzzy API - REST API Client Module

# Note: Config module must be loaded before this module
# The using module statement is handled in Main.ps1

class APIError : Exception {
    [int]$StatusCode
    [string]$ErrorMessage
    [string]$ErrorCode
    
    APIError([int]$statusCode, [string]$message, [string]$errorCode = $null) : base($message) {
        $this.StatusCode = $statusCode
        $this.ErrorMessage = $message
        $this.ErrorCode = $errorCode
    }
}

class CyberArkAPI {
    [object]$Config  # Using object to avoid parse-time type requirement
    [string]$Token
    [System.Collections.Hashtable]$SessionHeaders
    
    CyberArkAPI([object]$config) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($config.GetType().Name -ne "Config") {
            throw "Config parameter must be of type Config"
        }
        $this.Config = $config
        $this.SessionHeaders = @{
            "Content-Type" = "application/json"
        }
        
        # Load token from file if exists
        $tokenPath = $config.GetTokenPath()
        if (Test-Path $tokenPath) {
            $this.Token = (Get-Content $tokenPath -Raw).Trim()
        }
        
        # Disable SSL verification warnings if needed
        if (-not $config.VerifySSL) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        }
    }
    
    [string] GetBaseUrl() {
        return "$($this.Config.GetBaseUrl())/PasswordVault/API"
    }
    
    [void] SetToken([string]$token) {
        $this.Token = $token
        $this.Config.EnsureConfigDir()
        $tokenPath = $this.Config.GetTokenPath()
        Set-Content -Path $tokenPath -Value $token -NoNewline
    }
    
    [void] ClearToken() {
        $this.Token = $null
        $tokenPath = $this.Config.GetTokenPath()
        if (Test-Path $tokenPath) {
            Remove-Item $tokenPath -Force
        }
    }
    
    [System.Collections.Hashtable] GetHeaders() {
        $headers = $this.SessionHeaders.Clone()
        if ($this.Token) {
            $headers["Authorization"] = $this.Token
        }
        return $headers
    }
    
    [object] InvokeRequest([string]$method, [string]$endpoint, [hashtable]$data = $null, [hashtable]$params = $null) {
        $url = "$($this.GetBaseUrl())/$endpoint"
        $headers = $this.GetHeaders()
        
        try {
            $paramsString = ""
            if ($params) {
                $queryParams = $params.GetEnumerator() | ForEach-Object { 
                    $key = [System.Uri]::EscapeDataString($_.Key)
                    $value = [System.Uri]::EscapeDataString($_.Value.ToString())
                    "$key=$value"
                }
                $paramsString = "?" + ($queryParams -join "&")
            }
            
            $fullUrl = $url + $paramsString
            
            $splat = @{
                Uri = $fullUrl
                Method = $method
                Headers = $headers
                SkipCertificateCheck = (-not $this.Config.VerifySSL)
            }
            
            if ($data) {
                $body = $data | ConvertTo-Json -Depth 10
                $splat["Body"] = $body
            }
            
            $response = Invoke-RestMethod @splat -ErrorAction Stop
            
            # Return response if it exists, otherwise return null
            if ($response) {
                return $response
            }
            return $null
        }
        catch {
            $statusCode = 0
            $errorMessage = $_.Exception.Message
            
            # Try to get status code from response
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                
                # Try to parse error from response
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                    
                    if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
                        $errorData = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($errorData -and $errorData.ErrorMessage) {
                            $errorMessage = $errorData.ErrorMessage
                        }
                        if ($errorData -and $errorData.ErrorCode) {
                            throw [APIError]::new($statusCode, $errorMessage, $errorData.ErrorCode)
                        }
                    }
                }
                catch {
                    # If parsing fails, use original error
                }
            }
            
            throw [APIError]::new($statusCode, $errorMessage, $null)
        }
    }
    
    [object] Get([string]$endpoint, [hashtable]$params = $null) {
        return $this.InvokeRequest("GET", $endpoint, $null, $params)
    }
    
    [object] Post([string]$endpoint, [hashtable]$data = $null) {
        return $this.InvokeRequest("POST", $endpoint, $data, $null)
    }
    
    [void] Delete([string]$endpoint) {
        $this.InvokeRequest("DELETE", $endpoint) | Out-Null
    }
    
    # Authentication
    [string] LogonRadius([string]$username, [string]$password, [bool]$concurrent = $true) {
        $data = @{
            username = $username
            password = $password
            concurrentSession = $concurrent
        }
        
        $url = "$($this.Config.GetBaseUrl())/PasswordVault/API/Auth/RADIUS/Logon"
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        try {
            $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body ($data | ConvertTo-Json) -SkipCertificateCheck:(-not $this.Config.VerifySSL)
            
            # Token is returned as a quoted string
            # Use a different variable name to avoid conflict with class property
            $sessionToken = $response.ToString().Trim('"')
            $this.SetToken($sessionToken)
            return $sessionToken
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorMessage = $_.Exception.Message
            throw [APIError]::new($statusCode, $errorMessage, $null)
        }
    }
    
    [void] Logoff() {
        if ($this.Token) {
            try {
                $this.Post("Auth/Logoff") | Out-Null
            }
            catch {
                # Ignore errors on logoff
            }
            $this.ClearToken()
        }
    }
    
    [bool] VerifySession() {
        if (-not $this.Token) {
            return $false
        }
        
        try {
            $this.Get("Safes", @{limit = 1}) | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
    
    # Safes
    [object[]] ListSafes([string]$search = $null, [int]$limit = 100) {
        $params = @{limit = $limit}
        if ($search) {
            $params["search"] = $search
        }
        $result = $this.Get("Safes", $params)
        return $result.value
    }
    
    # Accounts
    [object[]] SearchAccounts([string]$search, [int]$limit = 100) {
        $params = @{
            search = $search
            limit = $limit
        }
        $result = $this.Get("Accounts", $params)
        return $result.value
    }
    
    [object] GetAccount([string]$accountId) {
        return $this.Get("Accounts/$accountId")
    }
    
    [string] GetAccountPassword([string]$accountId) {
        $result = $this.Post("Accounts/$accountId/Password/Retrieve")
        return $result
    }
    
    [void] VerifyAccount([string]$accountId) {
        $this.Post("Accounts/$accountId/Verify") | Out-Null
    }
    
    [void] ChangeAccount([string]$accountId) {
        $this.Post("Accounts/$accountId/Change") | Out-Null
    }
    
    [void] DeleteAccount([string]$accountId) {
        $this.Delete("Accounts/$accountId")
    }
    
    # SSH Keys
    [string] GetSSHKey() {
        $url = "$($this.Config.GetBaseUrl())/PasswordVault/API/Users/Secret/SSHKeys/Cache/"
        $data = @{
            keyPassword = ""
            formats = @("OpenSSH")
        }
        
        $headers = $this.GetHeaders()
        
        try {
            $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body ($data | ConvertTo-Json) -SkipCertificateCheck:(-not $this.Config.VerifySSL)
            
            foreach ($keyFormat in $response.value) {
                if ($keyFormat.format -eq "OpenSSH") {
                    return $keyFormat.privateKey
                }
            }
            
            return $null
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorMessage = $_.Exception.Message
            throw [APIError]::new($statusCode, $errorMessage, $null)
        }
    }
}

# Classes are automatically exported in PowerShell 5.1+
# No need for Export-ModuleMember -Class

