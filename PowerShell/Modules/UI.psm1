# CyberArk Fuzzy API - Interactive UI Module

# Note: Accounts module must be loaded before this module
# The using module statement is handled in Main.ps1

enum AccountAction {
    SSH
    GetPassword
    Info
    Verify
    SCPSend
    SCPReceive
    Change
    Delete
    Back
}

function Select-Account {
    param(
        [object[]]$Accounts  # Using object[] to avoid parse-time type requirement
    )
    
    if ($Accounts.Count -eq 0) {
        Write-Host "No accounts to select from" -ForegroundColor Yellow
        return $null
    }
    
    # Create choices for Out-GridView or simple selection
    $choices = @()
    for ($i = 0; $i -lt $Accounts.Count; $i++) {
        $choices += [PSCustomObject]@{
            Index = $i
            Display = $Accounts[$i].GetDisplayName()
            Account = $Accounts[$i]
        }
    }
    
    # Use Out-GridView for selection
    $selected = $choices | Out-GridView -Title "Select an account" -OutputMode Single
    
    if ($selected) {
        return $selected.Account
    }
    
    return $null
}

function Select-Action {
    # Get the AccountAction enum type dynamically
    $actionEnumType = $null
    $allTypes = [System.AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetTypes() }
    $actionEnumType = $allTypes | Where-Object { $_.Name -eq "AccountAction" -and $_.IsEnum } | Select-Object -First 1
    
    if (-not $actionEnumType) {
        Write-Host "Error: AccountAction enum not found" -ForegroundColor Red
        return $null
    }
    
    # Get enum values dynamically
    $enumValues = [Enum]::GetValues($actionEnumType)
    
    # Build actions list - map enum values to display names
    $actionMap = @{
        "SSH" = "SSH"
        "GetPassword" = "Get Password"
        "Info" = "Info"
        "Verify" = "Verify"
        "SCPSend" = "SCP Send"
        "SCPReceive" = "SCP Receive"
        "Change" = "Change"
        "Delete" = "Delete"
        "Back" = "← Back to search"
    }
    
    $actions = @()
    foreach ($enumValue in $enumValues) {
        $enumName = $enumValue.ToString()
        if ($actionMap.ContainsKey($enumName)) {
            $actions += [PSCustomObject]@{
                Value = $enumValue
                Name = $actionMap[$enumName]
            }
        }
    }
    
    Write-Host "`nSelect an action:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $actions.Count; $i++) {
        Write-Host "$($i + 1). $($actions[$i].Name)" -ForegroundColor White
    }
    
    $choice = Read-Host "Enter number"
    
    # Try to parse the choice
    try {
        $index = [int]$choice - 1
        
        if ($index -ge 0 -and $index -lt $actions.Count) {
            $selectedAction = $actions[$index].Value
            Write-Host "Selected: $($actions[$index].Name)" -ForegroundColor Gray
            Write-Host "DEBUG: In Select-Action - selectedAction: $selectedAction, Type: $($selectedAction.GetType().FullName), Value: $($selectedAction.ToString()), IsNull: $($null -eq $selectedAction)" -ForegroundColor DarkGray
            Write-Host "DEBUG: About to return from Select-Action" -ForegroundColor DarkGray
            $result = $selectedAction
            Write-Host "DEBUG: Return value stored in variable, returning now" -ForegroundColor DarkGray
            return $result
        } else {
            Write-Host "Invalid selection: $choice (must be 1-$($actions.Count))" -ForegroundColor Yellow
            return $null
        }
    }
    catch {
        Write-Host "Invalid input: $choice (must be a number)" -ForegroundColor Yellow
        return $null
    }
}

function Prompt-Search {
    return Read-Host "Search for accounts"
}

function Prompt-Path {
    param(
        [string]$Message,
        [string]$Default = ""
    )
    
    $path = Read-Host $Message
    if ([string]::IsNullOrWhiteSpace($path) -and -not [string]::IsNullOrWhiteSpace($Default)) {
        return $Default
    }
    return $path
}

function Confirm-Action {
    param(
        [string]$Message,
        [bool]$Default = $false
    )
    
    $defaultText = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host "$Message $defaultText"
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return $response.ToLower() -in @("y", "yes", "true", "1")
}

Export-ModuleMember -Function Select-Account, Select-Action, Prompt-Search, Prompt-Path, Confirm-Action
# Enums are automatically exported in PowerShell 5.1+
# No need for Export-ModuleMember -Enum

