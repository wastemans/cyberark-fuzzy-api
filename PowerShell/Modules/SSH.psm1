# CyberArk Fuzzy API - SSH/SCP Module

# Note: Config and Accounts modules must be loaded before this module
# The using module statements are handled in Main.ps1

class SSHManager {
    [object]$Config  # Using object to avoid parse-time type requirement
    [string]$SSHPath
    [string]$SCPPath
    
    SSHManager([object]$config) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($config.GetType().Name -ne "Config") {
            throw "Config parameter must be of type Config"
        }
        $this.Config = $config
        $this.SSHPath = $this.FindSSH()
        $this.SCPPath = $this.FindSCP()
    }
    
    [string] FindSSH() {
        if ($this.SSHPath) {
            return $this.SSHPath
        }
        
        # Try to find ssh
        $candidates = @(
            (Get-Command ssh -ErrorAction SilentlyContinue).Source,
            "C:\Windows\System32\OpenSSH\ssh.exe",
            "C:\Program Files\Git\usr\bin\ssh.exe"
        )
        
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path $candidate)) {
                return $candidate
            }
        }
        
        return "ssh"
    }
    
    [string] FindSCP() {
        if ($this.SCPPath) {
            return $this.SCPPath
        }
        
        $candidates = @(
            (Get-Command scp -ErrorAction SilentlyContinue).Source,
            "C:\Windows\System32\OpenSSH\scp.exe",
            "C:\Program Files\Git\usr\bin\scp.exe"
        )
        
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path $candidate)) {
                return $candidate
            }
        }
        
        return "scp"
    }
    
    [string] BuildConnectionString([object]$account) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        return "$($this.Config.Username)@$($account.Username)@$($account.Address)@$($this.Config.Endpoint)"
    }
    
    [int] Connect([object]$account, [bool]$useKey = $true) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        $connectionString = $this.BuildConnectionString($account)
        
        Write-Host "Connecting to $($account.Username)@$($account.Address)..." -ForegroundColor Cyan
        Write-Host "Connection string: $connectionString" -ForegroundColor Gray
        Write-Host "Press Ctrl+C or type 'exit' to disconnect and return to the menu." -ForegroundColor Yellow
        
        # Build SSH command arguments
        $sshArgs = @()
        
        # Add SSH key if available
        if ($useKey -and (Test-Path $this.Config.SSHKeyPath)) {
            $sshArgs += @("-i", $this.Config.SSHKeyPath)
            Write-Host "Using SSH key: $($this.Config.SSHKeyPath)" -ForegroundColor Gray
        }
        
        $sshArgs += $connectionString
        
        # Execute SSH directly in the current console
        # This will block until SSH exits (user types 'exit' or presses Ctrl+C)
        try {
            & $this.SSHPath $sshArgs
            $exitCode = $LASTEXITCODE
        }
        catch {
            Write-Host "SSH execution error: $($_.Exception.Message)" -ForegroundColor Red
            $exitCode = 1
        }
        
        if ($exitCode -ne 0 -and $exitCode -ne $null) {
            Write-Host "SSH session ended (exit code: $exitCode)" -ForegroundColor Yellow
        } else {
            Write-Host "SSH session ended normally" -ForegroundColor Green
        }
        
        return $exitCode
    }
    
    [int] SCPSend([object]$account, [string]$localPath, [string]$remotePath = "~/", [bool]$useKey = $true) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        $connectionString = $this.BuildConnectionString($account)
        
        $cmd = @($this.SCPPath, "-O")
        
        if ($useKey -and (Test-Path $this.Config.SSHKeyPath)) {
            $cmd += @("-i", $this.Config.SSHKeyPath)
        }
        
        $cmd += @($localPath, "$connectionString`:$remotePath")
        
        Write-Host "Sending $localPath to $($account.Address):$remotePath..." -ForegroundColor Cyan
        
        $process = Start-Process -FilePath $cmd[0] -ArgumentList $cmd[1..($cmd.Length-1)] -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Transfer complete" -ForegroundColor Green
        } else {
            Write-Host "Transfer failed (exit code: $($process.ExitCode))" -ForegroundColor Red
        }
        
        return $process.ExitCode
    }
    
    [int] SCPReceive([object]$account, [string]$remotePath, [string]$localPath = "./", [bool]$useKey = $true) {  # Using object to avoid parse-time type requirement
        # Runtime type check using type name string
        if ($account.GetType().Name -ne "Account") {
            throw "Account parameter must be of type Account"
        }
        $connectionString = $this.BuildConnectionString($account)
        
        $cmd = @($this.SCPPath, "-O")
        
        if ($useKey -and (Test-Path $this.Config.SSHKeyPath)) {
            $cmd += @("-i", $this.Config.SSHKeyPath)
        }
        
        $cmd += @("$connectionString`:$remotePath", $localPath)
        
        Write-Host "Receiving $remotePath from $($account.Address)..." -ForegroundColor Cyan
        
        $process = Start-Process -FilePath $cmd[0] -ArgumentList $cmd[1..($cmd.Length-1)] -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Transfer complete: $localPath" -ForegroundColor Green
        } else {
            Write-Host "Transfer failed (exit code: $($process.ExitCode))" -ForegroundColor Red
        }
        
        return $process.ExitCode
    }
}

# Classes are automatically exported in PowerShell 5.1+
# No need for Export-ModuleMember -Class

