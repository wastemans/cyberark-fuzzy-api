# CyberArk Fuzzy API - Configuration Module

class Config {
    [string]$Endpoint = "cyberark"
    [string]$Username = ""
    [bool]$VerifySSL = $false
    
    [string]$SSHKeyPath = ""
    [int]$KeyMaxAgeHours = 9
    
    [int]$KeepaliveMinSeconds = 901   # 15:01
    [int]$KeepaliveMaxSeconds = 1139  # 18:59
    [double]$KeepaliveTimeoutHours = 9.0
    
    [bool]$RichOutput = $true
    [string]$DefaultSearch = ""
    
    Config() {
        if ([string]::IsNullOrEmpty($this.SSHKeyPath)) {
            $configDir = [string]$this.GetConfigDir()
            $this.SSHKeyPath = Join-Path -Path $configDir -ChildPath "key.openssh"
        }
    }
    
    [string] GetBaseUrl() {
        return "https://$($this.Endpoint)"
    }
    
    [string] GetConfigDir() {
        # Get the directory where this script/module lives
        $scriptPath = $PSScriptRoot
        if ([string]::IsNullOrEmpty($scriptPath)) {
            # If running as script, get script directory
            $tempPath = Split-Path -Parent $MyInvocation.MyCommand.Path
            # Handle array result from Split-Path
            if ($tempPath -is [array]) {
                $scriptPath = [string]$tempPath[0]
            } else {
                $scriptPath = [string]$tempPath
            }
        } else {
            # Ensure we have a string, not an array
            if ($scriptPath -is [array]) {
                $scriptPath = [string]$scriptPath[0]
            } else {
                $scriptPath = [string]$scriptPath
            }
        }
        
        # Go up one level from Modules to PowerShell directory, then up to project root
        $tempModulesDir = Split-Path -Parent $scriptPath
        if ($tempModulesDir -is [array]) {
            $modulesDir = [string]$tempModulesDir[0]
        } else {
            $modulesDir = [string]$tempModulesDir
        }
        
        $tempProjectRoot = Split-Path -Parent $modulesDir
        if ($tempProjectRoot -is [array]) {
            $projectRoot = [string]$tempProjectRoot[0]
        } else {
            $projectRoot = [string]$tempProjectRoot
        }
        
        return $projectRoot
    }
    
    [string] GetTokenPath() {
        $configDir = [string]$this.GetConfigDir()
        return Join-Path -Path $configDir -ChildPath "token"
    }
    
    [string] GetKeepalivePidPath() {
        $configDir = [string]$this.GetConfigDir()
        return Join-Path -Path $configDir -ChildPath "keepalive.pid"
    }
    
    [string] GetKeepaliveLogPath() {
        $configDir = [string]$this.GetConfigDir()
        return Join-Path -Path $configDir -ChildPath "keepalive.log"
    }
    
    [void] EnsureConfigDir() {
        $dir = [string]$this.GetConfigDir()
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Get-ConfigFile {
    param(
        [string]$ProjectRoot
    )
    
    # Ensure ProjectRoot is a string, not an array
    if ($ProjectRoot -is [array]) {
        $ProjectRoot = $ProjectRoot[0]
    }
    $ProjectRoot = [string]$ProjectRoot
    
    $currentLocation = [string](Get-Location).Path
    # Build candidates array one at a time to avoid array issues
    $candidates = @()
    $candidates += Join-Path -Path $currentLocation -ChildPath "config.ini"
    $candidates += Join-Path -Path $ProjectRoot -ChildPath "config.ini"
    $candidates += Join-Path -Path $ProjectRoot -ChildPath "config.ini.example"
    
    foreach ($path in $candidates) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

function ConvertTo-Bool {
    param([string]$Value)
    
    $value = $Value.Trim().ToLower()
    return $value -in @("true", "yes", "1", "on")
}

function Get-Config {
    param(
        [string]$Endpoint = $null,
        [string]$Username = $null
    )
    
    $config = [Config]::new()
    
    # Get project root and ensure it's a string
    $projectRoot = $config.GetConfigDir()
    if ($projectRoot -is [array]) {
        $projectRoot = $projectRoot[0]
    }
    $projectRoot = [string]$projectRoot
    
    # Find and parse config file
    $configFile = Get-ConfigFile -ProjectRoot $projectRoot
    
    if ($configFile -and (Test-Path $configFile)) {
        $iniContent = Get-IniContent -FilePath $configFile
        
        # [cyberark] section
        if ($iniContent.ContainsKey("cyberark")) {
            $cyberark = $iniContent["cyberark"]
            if ($cyberark.ContainsKey("endpoint")) {
                $config.Endpoint = $cyberark["endpoint"]
            }
            if ($cyberark.ContainsKey("username")) {
                $config.Username = $cyberark["username"]
            }
            if ($cyberark.ContainsKey("verify_ssl")) {
                $config.VerifySSL = ConvertTo-Bool -Value $cyberark["verify_ssl"]
            }
        }
        
        # [ssh] section
        if ($iniContent.ContainsKey("ssh")) {
            $ssh = $iniContent["ssh"]
            if ($ssh.ContainsKey("ssh_key_path")) {
                $keyPath = $ssh["ssh_key_path"].Trim()
                # Ensure keyPath is a string, not an array
                if ($keyPath -is [array]) {
                    $keyPath = $keyPath[0]
                }
                $keyPath = [string]$keyPath
                if (-not [string]::IsNullOrEmpty($keyPath)) {
                    if ([System.IO.Path]::IsPathRooted($keyPath)) {
                        $config.SSHKeyPath = $keyPath
                    } else {
                        $config.SSHKeyPath = Join-Path -Path ([string]$projectRoot) -ChildPath $keyPath
                    }
                }
            }
            if ($ssh.ContainsKey("key_max_age_hours")) {
                $config.KeyMaxAgeHours = [int]$ssh["key_max_age_hours"]
            }
        }
        
        # [keepalive] section
        if ($iniContent.ContainsKey("keepalive")) {
            $keepalive = $iniContent["keepalive"]
            if ($keepalive.ContainsKey("min_seconds")) {
                $config.KeepaliveMinSeconds = [int]$keepalive["min_seconds"]
            }
            if ($keepalive.ContainsKey("max_seconds")) {
                $config.KeepaliveMaxSeconds = [int]$keepalive["max_seconds"]
            }
            if ($keepalive.ContainsKey("timeout_hours")) {
                $config.KeepaliveTimeoutHours = [double]$keepalive["timeout_hours"]
            }
        }
        
        # [ui] section
        if ($iniContent.ContainsKey("ui")) {
            $ui = $iniContent["ui"]
            if ($ui.ContainsKey("rich_output")) {
                $config.RichOutput = ConvertTo-Bool -Value $ui["rich_output"]
            }
            if ($ui.ContainsKey("default_search")) {
                $config.DefaultSearch = $ui["default_search"].Trim()
            }
        }
    }
    
    # CLI overrides take precedence
    if ($Endpoint) {
        $config.Endpoint = $Endpoint
    }
    if ($Username) {
        $config.Username = $Username
    }
    
    # Ensure ssh_key_path is set
    if ([string]::IsNullOrEmpty($config.SSHKeyPath)) {
        $config.SSHKeyPath = Join-Path -Path ([string]$projectRoot) -ChildPath "key.openssh"
    }
    
    return $config
}

function Get-IniContent {
    param([string]$FilePath)
    
    $ini = @{}
    $section = $null
    
    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#") -or $line.StartsWith(";")) {
            return
        }
        
        # Section header
        if ($line -match '^\[(.+)\]$') {
            $section = $matches[1]
            if (-not $ini.ContainsKey($section)) {
                $ini[$section] = @{}
            }
        }
        # Key=Value
        elseif ($line -match '^([^=]+)=(.*)$' -and $section) {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $ini[$section][$key] = $value
        }
    }
    
    return $ini
}

Export-ModuleMember -Function Get-Config, Get-ConfigFile, ConvertTo-Bool, Get-IniContent

