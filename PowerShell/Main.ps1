# CyberArk Fuzzy API - Main Entry Point
# Interactive CyberArk account management

# Get script directory first (before param block if possible, but param must come first)
param(
    [Parameter(Position=0)]
    [string]$Search,
    
    [Parameter()]
    [Alias("e")]
    [string]$Endpoint,
    
    [Parameter()]
    [Alias("u")]
    [string]$Username,
    
    [Parameter()]
    [switch]$SavePassword
)

# Get script directory - use PSScriptRoot if available, otherwise calculate
if ($PSScriptRoot) {
    $scriptPath = $PSScriptRoot
} else {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}
# Ensure scriptPath is a string, not an array
if ($scriptPath -is [array]) {
    $scriptPath = $scriptPath[0]
}
$scriptPath = [string]$scriptPath
$modulesPath = Join-Path -Path $scriptPath -ChildPath "Modules"

# Load class definitions by reading and executing module content
# This makes classes available without triggering file associations
# We filter out Export-ModuleMember calls since they can only run in module scope
$ErrorActionPreference = "Stop"
try {
    # Helper function to load classes from module file
    function Load-ModuleClasses {
        param([string]$ModulePath)
        $content = Get-Content $ModulePath -Raw
        # Remove Export-ModuleMember lines and comments about it
        $content = $content -replace '(?m)^.*Export-ModuleMember.*$', ''
        $content = $content -replace '(?m)^.*# Classes are automatically exported.*$', ''
        # Execute the content to load classes
        Invoke-Expression $content
    }
    
    # Load Config module classes and functions
    Load-ModuleClasses (Join-Path -Path $modulesPath -ChildPath "Config.psm1")
    Import-Module (Join-Path -Path $modulesPath -ChildPath "Config.psm1") -Force -Global -ErrorAction Stop
    
    # Load Api module classes and functions
    Load-ModuleClasses (Join-Path -Path $modulesPath -ChildPath "Api.psm1")
    Import-Module (Join-Path -Path $modulesPath -ChildPath "Api.psm1") -Force -Global -ErrorAction Stop
    
    # Load Accounts module classes and functions
    Load-ModuleClasses (Join-Path -Path $modulesPath -ChildPath "Accounts.psm1")
    Import-Module (Join-Path -Path $modulesPath -ChildPath "Accounts.psm1") -Force -Global -ErrorAction Stop
    
    # Load Auth module classes and functions
    Load-ModuleClasses (Join-Path -Path $modulesPath -ChildPath "Auth.psm1")
    Import-Module (Join-Path -Path $modulesPath -ChildPath "Auth.psm1") -Force -Global -ErrorAction Stop
    
    # Load SSH module classes and functions
    Load-ModuleClasses (Join-Path -Path $modulesPath -ChildPath "SSH.psm1")
    Import-Module (Join-Path -Path $modulesPath -ChildPath "SSH.psm1") -Force -Global -ErrorAction Stop
    
    # Load UI module classes and functions
    Load-ModuleClasses (Join-Path -Path $modulesPath -ChildPath "UI.psm1")
    Import-Module (Join-Path -Path $modulesPath -ChildPath "UI.psm1") -Force -Global -ErrorAction Stop
    
    # Verify types are available
    $requiredTypes = @("Config", "CyberArkAPI", "Account", "AccountManager", "AuthManager", "SSHManager")
    $missingTypes = @()
    foreach ($typeName in $requiredTypes) {
        try {
            $type = [Type]::GetType($typeName)
            if (-not $type) {
                # Try to find in loaded assemblies
                $type = [System.AppDomain]::CurrentDomain.GetAssemblies() | 
                    ForEach-Object { $_.GetTypes() } | 
                    Where-Object { $_.Name -eq $typeName } | 
                    Select-Object -First 1
            }
            if (-not $type) {
                $missingTypes += $typeName
            }
        }
        catch {
            $missingTypes += $typeName
        }
    }
    
    if ($missingTypes.Count -gt 0) {
        Write-Host "Warning: Some types not found: $($missingTypes -join ', ')" -ForegroundColor Yellow
        Write-Host "This may cause issues. Available types:" -ForegroundColor Yellow
        Get-Type | Where-Object { $_.Name -match "^(Config|CyberArkAPI|Account|AuthManager|AccountManager|SSHManager)$" } | ForEach-Object { Write-Host "  - $($_.Name)" }
    }
}
catch {
    Write-Host "Error loading modules: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Module path: $modulesPath" -ForegroundColor Yellow
    if ($_.Exception.InnerException) {
        Write-Host "Inner exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
    exit 1
}
finally {
    $ErrorActionPreference = "Continue"
}

function Handle-Action {
    param(
        [object]$Action,  # Using object to avoid parse-time type requirement (AccountAction enum)
        [object]$Account,  # Using object to avoid parse-time type requirement
        [object]$AccountMgr,  # Using object to avoid parse-time type requirement
        [object]$SSHMgr  # Using object to avoid parse-time type requirement
    )
    
    # Convert action to string for comparison (works with enum values loaded via Invoke-Expression)
    $actionName = $Action.ToString()
    
    # Debug output
    Write-Host "Handling action: $actionName (type: $($Action.GetType().Name))" -ForegroundColor Gray
    
    switch ($actionName) {
        "SSH" {
            try {
                # Build connection string using reflection to call BuildConnectionString
                $buildMethod = $SSHMgr.GetType().GetMethod("BuildConnectionString")
                $connectionString = $buildMethod.Invoke($SSHMgr, @($Account))
                
                Write-Host "Connecting to $($Account.Username)@$($Account.Address)..." -ForegroundColor Cyan
                Write-Host "Connection string: $connectionString" -ForegroundColor Gray
                Write-Host "Press Ctrl+C or type 'exit' to disconnect and return to the menu." -ForegroundColor Yellow
                
                # Build SSH command arguments
                $sshArgs = @()
                
                # Add SSH key if available
                $sshKeyPath = $SSHMgr.Config.SSHKeyPath
                if ($sshKeyPath -and (Test-Path $sshKeyPath)) {
                    $sshArgs += @("-i", $sshKeyPath)
                    Write-Host "Using SSH key: $sshKeyPath" -ForegroundColor Gray
                }
                
                $sshArgs += $connectionString
                
                # Execute SSH - PowerShell's console I/O interferes with interactive sessions
                # Try to use Windows Terminal tabs (Windows 11), fall back to new window
                $sshPath = $SSHMgr.SSHPath
                
                # Build the command for display
                $displayCmd = "$sshPath " + ($sshArgs -join ' ')
                Write-Host "SSH Command: $displayCmd" -ForegroundColor Cyan
                
                # Check if Windows Terminal (wt.exe) is available
                $wtPath = $null
                try {
                    $wtCommand = Get-Command wt -ErrorAction Stop
                    $wtPath = $wtCommand.Source
                }
                catch {
                    # Try common locations
                    $wtCandidates = @(
                        "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
                    )
                    
                    foreach ($candidate in $wtCandidates) {
                        if ($candidate -and (Test-Path $candidate -ErrorAction SilentlyContinue)) {
                            $wtPath = $candidate
                            break
                        }
                    }
                    
                    # Also check Windows Apps folder with wildcard
                    if (-not $wtPath) {
                        $wildcardPath = "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminal_*\wt.exe"
                        $found = Get-ChildItem -Path $wildcardPath -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found) {
                            $wtPath = $found.FullName
                        }
                    }
                }
                
                if ($wtPath) {
                    # Use Windows Terminal to open SSH in a new tab
                    Write-Host "Opening SSH in new Windows Terminal tab..." -ForegroundColor Yellow
                    Write-Host "Close the SSH tab when done to return to the menu." -ForegroundColor Yellow
                    
                    # Build the SSH command with all arguments
                    # We need to properly quote arguments for cmd.exe
                    $sshCommandParts = @()
                    foreach ($arg in $sshArgs) {
                        if ($arg -match '\s' -or $arg.Contains('@')) {
                            # Escape quotes for cmd.exe: " becomes ""
                            $escaped = $arg -replace '"', '""'
                            $sshCommandParts += "`"$escaped`""
                        } else {
                            $sshCommandParts += $arg
                        }
                    }
                    $sshCommand = "$sshPath " + ($sshCommandParts -join ' ')
                    
                    # Build Windows Terminal arguments
                    # Format: wt.exe -w 0 new-tab cmd.exe /k "<ssh command>"
                    # Use Start-Process with proper argument array
                    $wtArguments = @(
                        "-w", "0",
                        "new-tab",
                        "cmd.exe",
                        "/k",
                        $sshCommand
                    )
                    
                    # Execute using Start-Process with argument array
                    Start-Process -FilePath $wtPath -ArgumentList $wtArguments
                    $exitCode = 0
                }
                else {
                    # Fall back to opening in a new window
                    Write-Host "Windows Terminal not found, opening SSH in new window..." -ForegroundColor Yellow
                    Write-Host "Close the SSH window when done to return to the menu." -ForegroundColor Yellow
                    
                    Start-Process -FilePath $sshPath -ArgumentList $sshArgs
                    $exitCode = 0  # Can't get exit code from new window
                }
                
                if ($exitCode -ne 0 -and $exitCode -ne $null) {
                    Write-Host "SSH session ended (exit code: $exitCode)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "SSH connection failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
            }
        }
        "GetPassword" {
            $password = $AccountMgr.GetPassword($Account)
            if ($password) {
                Write-Host "Password: $password" -ForegroundColor Green
            }
        }
        "Info" {
            $info = $AccountMgr.GetInfo($Account)
            if ($info) {
                $info | ConvertTo-Json -Depth 10 | Write-Host
            }
        }
        "Verify" {
            try {
                # Unwrap PSObject to actual account instance
                $accountObj = if ($Account -is [psobject] -and $Account.PSObject.BaseObject) { $Account.PSObject.BaseObject } else { $Account }
                
                # Use reflection to avoid optional/overload issues when classes are loaded via Invoke-Expression
                $verifyMethod = $AccountMgr.GetType().GetMethod("Verify")
                if ($verifyMethod) {
                    $verifyMethod.Invoke($AccountMgr, @($accountObj)) | Out-Null
                } else {
                    $AccountMgr.Verify($accountObj) | Out-Null
                }
            }
            catch {
                Write-Host "Verify failed: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.Exception.InnerException) {
                    Write-Host "Inner error: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
                }
            }
        }
        "SCPSend" {
            $localPath = Prompt-Path -Message "Local source path:"
            if ($localPath) {
                $remotePath = Prompt-Path -Message "Remote destination path:" -Default "~/"
                if ($remotePath) {
                    try {
                        # Use reflection to bypass optional-parameter resolution when classes are loaded via Invoke-Expression
                        $scpSendMethod = $SSHMgr.GetType().GetMethod("SCPSend")
                        
                        # Unwrap PSObject inputs and ensure strings for paths
                        $accountObj = if ($Account -is [psobject] -and $Account.PSObject.BaseObject) { $Account.PSObject.BaseObject } else { $Account }
                        $localStr   = [string]$localPath
                        $remoteStr  = [string]$remotePath
                        
                        if ($scpSendMethod) {
                            # Explicitly pass all parameters: account, localPath, remotePath, useKey
                            $scpSendMethod.Invoke($SSHMgr, @($accountObj, $localStr, $remoteStr, $true)) | Out-Null
                        } else {
                            # Fallback to direct call with all params
                            $SSHMgr.SCPSend($accountObj, $localStr, $remoteStr, $true) | Out-Null
                        }
                    }
                    catch {
                        Write-Host "SCP Send failed: $($_.Exception.Message)" -ForegroundColor Red
                        if ($_.Exception.InnerException) {
                            Write-Host "Inner error: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        "SCPReceive" {
            $remotePath = Prompt-Path -Message "Remote source path:"
            if ($remotePath) {
                $localPath = Prompt-Path -Message "Local destination path:" -Default "./"
                if ($localPath) {
                    try {
                        # Use reflection to bypass optional-parameter resolution when classes are loaded via Invoke-Expression
                        $scpReceiveMethod = $SSHMgr.GetType().GetMethod("SCPReceive")
                        
                        # Unwrap PSObject inputs and ensure strings for paths
                        $accountObj = if ($Account -is [psobject] -and $Account.PSObject.BaseObject) { $Account.PSObject.BaseObject } else { $Account }
                        $remoteStr  = [string]$remotePath
                        $localStr   = [string]$localPath
                        
                        if ($scpReceiveMethod) {
                            # Explicitly pass all parameters: account, remotePath, localPath, useKey
                            $scpReceiveMethod.Invoke($SSHMgr, @($accountObj, $remoteStr, $localStr, $true)) | Out-Null
                        } else {
                            # Fallback to direct call with all params
                            $SSHMgr.SCPReceive($accountObj, $remoteStr, $localStr, $true) | Out-Null
                        }
                    }
                    catch {
                        Write-Host "SCP Receive failed: $($_.Exception.Message)" -ForegroundColor Red
                        if ($_.Exception.InnerException) {
                            Write-Host "Inner error: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        "Change" {
            if (Confirm-Action -Message "Change password for $($Account.Username)@$($Account.Address)?" -Default $false) {
                $AccountMgr.Change($Account)
            }
        }
        "Delete" {
            try {
                # Unwrap PSObject to actual account instance
                $accountObj = if ($Account -is [psobject] -and $Account.PSObject.BaseObject) { $Account.PSObject.BaseObject } else { $Account }
                
                # Use reflection and explicitly pass both parameters to avoid optional param resolution issues
                $deleteMethod = $AccountMgr.GetType().GetMethod("Delete")
                if ($deleteMethod) {
                    $deleteMethod.Invoke($AccountMgr, @($accountObj, $true)) | Out-Null
                } else {
                    $AccountMgr.Delete($accountObj, $true) | Out-Null
                }
            }
            catch {
                Write-Host "Delete failed: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.Exception.InnerException) {
                    Write-Host "Inner error: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
                }
            }
        }
        "Back" {
            return $false
        }
        default {
            Write-Host "Unknown action: $actionName" -ForegroundColor Red
            Write-Host "DEBUG: Falling through to default case, returning true" -ForegroundColor DarkGray
            return $true  # Continue loop to allow retry
        }
    }
    
    # All cases should return, but if we get here, return true to continue
    Write-Host "DEBUG: Reached end of Handle-Action, returning true" -ForegroundColor DarkGray
    return $true
}

# Main execution
try {
    # Initialize components
    $config = Get-Config -Endpoint $Endpoint -Username $Username
    $config.EnsureConfigDir()
    
    # Create instances by finding the Type objects and using Activator::CreateInstance
    # This works even when New-Object can't find the types
    try {
        # Get the types from loaded assemblies
        $allTypes = [System.AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetTypes() }
        
        $cyberArkApiType = $allTypes | Where-Object { $_.Name -eq "CyberArkAPI" -and -not $_.IsAbstract } | Select-Object -First 1
        $authManagerType = $allTypes | Where-Object { $_.Name -eq "AuthManager" -and -not $_.IsAbstract } | Select-Object -First 1
        $accountManagerType = $allTypes | Where-Object { $_.Name -eq "AccountManager" -and -not $_.IsAbstract } | Select-Object -First 1
        $sshManagerType = $allTypes | Where-Object { $_.Name -eq "SSHManager" -and -not $_.IsAbstract } | Select-Object -First 1
        
        if (-not $cyberArkApiType) {
            throw "Could not find CyberArkAPI type"
        }
        
        # Create instances using Activator::CreateInstance
        $api = [Activator]::CreateInstance($cyberArkApiType, $config)
        $authMgr = [Activator]::CreateInstance($authManagerType, $config, $api)
        $accountMgr = [Activator]::CreateInstance($accountManagerType, $api)
        $sshMgr = [Activator]::CreateInstance($sshManagerType, $config)
    }
    catch {
        Write-Host "Error creating instances: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.Exception.ScriptStackTrace)" -ForegroundColor Yellow
        exit 1
    }
    
    # Authenticate
    if (-not $authMgr.CheckAndRefresh()) {
        if (-not $authMgr.Authenticate($SavePassword)) {
            Write-Host "Authentication failed. Exiting." -ForegroundColor Red
            exit 1
        }
    }
    
    # Start keepalive as background job - explicitly pass timeout to avoid parameter resolution issues
    # When classes are loaded via Invoke-Expression, optional parameters may not work correctly
    $authMgr.StartKeepalive($config.KeepaliveTimeoutHours)
    
    # Download SSH key for default endpoint
    if ($config.Endpoint -eq "cyberark") {
        $authMgr.DownloadSSHKey()
    }
    else {
        Write-Host "Alternate endpoint - skipping SSH key download" -ForegroundColor Yellow
    }
    
    # Main loop
    $searchTerm = $Search
    
    while ($true) {
        # Get search term if not provided
        if ([string]::IsNullOrWhiteSpace($searchTerm)) {
            $searchTerm = Prompt-Search
            if ([string]::IsNullOrWhiteSpace($searchTerm)) {
                break
            }
        }
        
        # Check auth is still valid
        if (-not $authMgr.CheckAndRefresh()) {
            Write-Host "Authentication lost. Exiting." -ForegroundColor Red
            exit 1
        }
        
        # Search for accounts
        Write-Host "Searching for: $searchTerm" -ForegroundColor Cyan
        $accounts = $accountMgr.Search($searchTerm)
        
        if ($accounts.Count -eq 0) {
            Write-Host "No accounts found" -ForegroundColor Yellow
            $searchTerm = $null
            continue
        }
        
        # Select account
        $account = Select-Account -Accounts $accounts
        if (-not $account) {
            $searchTerm = $null
            continue
        }
        
        # Action loop for selected account
        while ($true) {
            # Call Select-Action directly
            $action = Select-Action
            
            # Debug immediately after getting action - check BEFORE any null checks
            Write-Host "DEBUG: Immediately after Select-Action call" -ForegroundColor DarkGray
            Write-Host "DEBUG: action variable exists: $($null -ne $action)" -ForegroundColor DarkGray
            if ($null -ne $action) {
                Write-Host "DEBUG: action type: $($action.GetType().FullName), value: $($action.ToString())" -ForegroundColor DarkGray
            } else {
                Write-Host "DEBUG: action is null" -ForegroundColor DarkGray
            }
            
            # Check if action is null - enum values from Invoke-Expression might need explicit null check
            if ($null -eq $action) {
                Write-Host "No action selected (null check), returning to search..." -ForegroundColor Yellow
                break
            }
            
            # Additional check - sometimes enum values evaluate as false even when not null
            try {
                $actionStr = $action.ToString()
                if ([string]::IsNullOrWhiteSpace($actionStr)) {
                    Write-Host "Action string is empty, returning to search..." -ForegroundColor Yellow
                    break
                }
                Write-Host "DEBUG: Action string is: '$actionStr'" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "Error converting action to string: $($_.Exception.Message)" -ForegroundColor Red
                break
            }
            
            # Handle the action
            try {
                $shouldContinue = Handle-Action -Action $action -Account $account -AccountMgr $accountMgr -SSHMgr $sshMgr
                if (-not $shouldContinue) {
                    # User selected "Back" - break out of action loop to return to search
                    Write-Host "Action handler returned false (Back selected), returning to search..." -ForegroundColor Yellow
                    break
                }
            }
            catch {
                Write-Host "Error in action handler: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Error type: $($_.Exception.GetType().Name)" -ForegroundColor Yellow
                if ($_.Exception.InnerException) {
                    Write-Host "Inner error: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
                }
                Write-Host "Continuing with action menu..." -ForegroundColor Yellow
                # Continue the loop to allow user to try another action
            }
            
            # Check auth after action (skip immediately after SSH to avoid interrupting)
            $actionName = $action.ToString()
            if ($actionName -ne "SSH") {
                if (-not $authMgr.CheckAndRefresh()) {
                    Write-Host "Authentication lost." -ForegroundColor Red
                    break
                }
            }
            
            # Prompt to continue (skip after SSH since user just returned from SSH session)
            if ($actionName -ne "SSH") {
                Read-Host "`nPress Enter to continue"
            } else {
                Write-Host "`nReturned from SSH session. Select another action or choose 'Back' to search again." -ForegroundColor Cyan
            }
        }
        
        # Reset search for next iteration
        $searchTerm = $null
    }
}
catch {
    Write-Host "`nInterrupted" -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    # Cleanup: Stop keepalive background job when script exits
    try {
        if ($authMgr) {
            $authMgr.StopKeepalive()
        }
    }
    catch {
        # Ignore cleanup errors
    }
}

