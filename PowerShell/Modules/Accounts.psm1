# CyberArk Fuzzy API - Account Management Module

# Note: Api module must be loaded before this module
# The using module statement is handled in Main.ps1

class Account {
    [string]$Id
    [string]$Address
    [string]$Username
    [string]$PlatformId
    [string]$SafeName
    [string]$Status
    
    Account() {}
    
    Account([hashtable]$data) {
        $this.Id = $data.id
        $this.Address = $data.address
        $this.Username = $data.userName
        $this.PlatformId = $data.platformId
        $this.SafeName = $data.safeName
        $this.Status = $data.secretManagement.status
    }
    
    [string] GetDisplayName() {
        return "$($this.Id) | $($this.Address) | $($this.Username) | $($this.Status)"
    }
}

class AccountManager {
    [object]$Api  # Using object to avoid parse-time type requirement
    
    AccountManager([object]$api) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($api.GetType().Name -ne "CyberArkAPI") {
            throw "Api parameter must be of type CyberArkAPI"
        }
        $this.Api = $api
    }
    
    [object[]] Search([string]$query) {  # Using object[] to avoid parse-time type requirement
        try {
            # Use reflection to call method to avoid overload resolution issues with Invoke-Expression loaded classes
            $method = $this.Api.GetType().GetMethod("SearchAccounts")
            if ($method) {
                $results = $method.Invoke($this.Api, @($query, 100))
            } else {
                # Fallback to direct call
                $results = $this.Api.SearchAccounts($query, 100)
            }
            $accounts = @()
            $accountType = [System.AppDomain]::CurrentDomain.GetAssemblies() | 
                ForEach-Object { $_.GetTypes() } | 
                Where-Object { $_.Name -eq "Account" -and -not $_.IsAbstract } | 
                Select-Object -First 1
            foreach ($result in $results) {
                # Convert result to hashtable (API returns PSCustomObject, constructor needs hashtable)
                $hashResult = @{}
                if ($result -is [hashtable]) {
                    $hashResult = $result
                } else {
                    # Convert PSCustomObject to hashtable
                    $result.PSObject.Properties | ForEach-Object { 
                        $hashResult[$_.Name] = $_.Value 
                    }
                }
                
                if ($accountType) {
                    $accounts += [Activator]::CreateInstance($accountType, $hashResult)
                } else {
                    # Fallback - try direct call with hashtable
                    $accounts += [Account]::new($hashResult)
                }
            }
            return $accounts
        }
        catch {
            Write-Host "Search failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Yellow
            if ($_.Exception.InnerException) {
                Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
            }
            return @()
        }
    }
    
    [string] GetPassword([object]$account) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        try {
            return $this.Api.GetAccountPassword($account.Id)
        }
        catch {
            Write-Host "Failed to get password: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    
    [object] GetInfo([object]$account) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        try {
            return $this.Api.GetAccount($account.Id)
        }
        catch {
            Write-Host "Failed to get account info: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    
    [bool] Verify([object]$account) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        try {
            $this.Api.VerifyAccount($account.Id)
            Write-Host "Verification triggered for $($account.Username)@$($account.Address)" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Verification failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    [bool] Change([object]$account) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        try {
            $this.Api.ChangeAccount($account.Id)
            Write-Host "Change triggered for $($account.Username)@$($account.Address)" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Change failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    [bool] Delete([object]$account, [bool]$confirm = $true) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        if ($confirm) {
            Write-Host "About to delete: $($account.Username)@$($account.Address)" -ForegroundColor Red
            $response = Read-Host "Are you sure? (yes/no)"
            if ($response.ToLower() -ne "yes") {
                Write-Host "Cancelled" -ForegroundColor Yellow
                return $false
            }
        }
        
        try {
            $this.Api.DeleteAccount($account.Id)
            Write-Host "Deleted $($account.Username)@$($account.Address)" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Delete failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    [void] DisplayAccounts([object[]]$accounts) {  # Using object[] to avoid parse-time type requirement
        $table = $accounts | Format-Table -Property Id, Address, Username, PlatformId, SafeName, Status -AutoSize
        Write-Host $table
    }
}

# Classes are automatically exported in PowerShell 5.1+
# No need for Export-ModuleMember -Class

